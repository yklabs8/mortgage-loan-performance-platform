"""Load one raw Freddie data file as-is into an ODS table, replacing that release's data for that file as a whole.

Usage: python python/load_ods.py <release_id> <ODS table> <data file>
Example: python python/load_ods.py R47 ods_orig data/.../sample_orig_2010.txt
Modeled on the official python-oracledb sample load_csv.py: batched executemany, reporting the line numbers that fail.
Reruns: the real ODS tables are partitioned by release + file; the file is loaded into a staging table, its fingerprint
is checked, and the staging table is then swapped with the matching partition.
Small non-partitioned test tables still use the original delete-then-insert logic in one transaction.
A release has files for several origination years; they are told apart by file name and do not affect each other.
A bad line while loading the staging table rolls back the whole batch; if the exchange DDL fails, the staging table is
kept and the real partition is not cleaned up blindly.
Requires: python/db.py; ODS tables already created. Called by: run manually.
"""

import csv  # split each line on the delimiter
import os  # take the file name from a path
import re  # check the table-name format
import sys  # read command-line arguments

from db import connect  # database connection

# rows per batch (project convention; the official sample recommends a large value to reduce round trips)
BATCH_SIZE = 50_000


# insert one batch, return the rows that failed (line number, error)
def insert(cur, sql, batch, first_line):
    # insert a batch at once, recording failed rows
    cur.executemany(sql, batch, batcherrors=True)
    return [(first_line + e.offset, e.message) for e in cur.getbatcherrors()]


def load_partitioned(conn, cur, release_id, table, data_path, cols, n, source_file):
    """Load the staging table, then call the database partition-exchange procedure; keep the staging table for inspection if the DDL fails."""
    if not re.fullmatch(r"[A-Za-z0-9_]+", release_id):
        raise ValueError(f"Invalid release_id format: {release_id}")
    if not re.fullmatch(r"[A-Za-z0-9_.]+", source_file):
        raise ValueError(f"Invalid file name format: {source_file}")
    stage = f"{table}_stage"
    cur.execute(f"select count(*) from {stage}")
    if cur.fetchone()[0] != 0:
        raise RuntimeError(
            f"{stage} is not empty; check the state of the last exchange first, it must not be overwritten"
        )
    cur.execute(
        "select status from user_indexes where index_name = upper(:n)",
        n=f"{stage}_pk",
    )
    index_row = cur.fetchone()
    if index_row is None or index_row[0] != "VALID":
        raise RuntimeError(f"The primary-key index of {stage} is unusable; cannot load")

    binds = ", ".join(f":{i + 1}" for i in range(n + 2))
    sql = f"insert into {stage} ({', '.join(cols)}) values ({binds})"
    rows, batch, errors = 0, [], []
    with open(data_path, encoding="utf-8", newline="") as f:
        for row in csv.reader(f, delimiter="|", quoting=csv.QUOTE_NONE):
            rows += 1
            if len(row) != n:
                raise ValueError(
                    f"Line {rows} has {len(row)} columns, {table} needs {n}"
                )
            batch.append(row + [release_id, source_file])
            if len(batch) == BATCH_SIZE:
                errors += insert(cur, sql, batch, rows - len(batch) + 1)
                batch = []
    if batch:
        errors += insert(cur, sql, batch, rows - len(batch) + 1)
    if errors:
        conn.rollback()
        for line, msg in errors[:10]:
            print(f"Line {line} could not be loaded: {msg}", file=sys.stderr)
        raise RuntimeError(
            f"{len(errors)} rows could not be loaded; the staging table was rolled back"
        )
    if rows == 0:
        raise ValueError(f"{data_path} is empty")
    cur.execute(f"select count(*) from {stage}")
    loaded = cur.fetchone()[0]
    if loaded != rows:
        raise RuntimeError(
            f"File has {rows} rows, staging table has {loaded}; mismatch, rolled back"
        )
    cur.execute(
        "select ods_file_hash(:t, :r, :f) from dual",
        t=stage,
        r=release_id,
        f=source_file,
    )
    expected_hash = cur.fetchone()[0]
    # persist the staging segment on its own; the exchange DDL cannot share a transaction with the load
    conn.commit()
    cur.callproc("ods_exchange_file", [table, release_id, source_file, expected_hash])
    print(
        f"{table} {release_id} {source_file}: file {rows} rows; after exchange {expected_hash}"
    )
    return rows


# load one file; return the row count on success
def load(release_id, table, data_path):
    # table name must be lower case and start with ods_
    if not re.fullmatch(r"ods_[a-z0-9_]+", table):
        # so that no other table becomes the target
        raise ValueError(f"Invalid table name: {table}")
    with connect() as conn, conn.cursor() as cur:  # connect to the database
        cur.execute(  # read the table's column names in column order
            "select lower(column_name) from user_tab_columns"
            " where table_name = upper(:t) order by column_id",
            t=table,
        )
        cols = [r[0] for r in cur]  # list of column names
        # the table does not exist, or its last two columns are wrong
        if cols[-2:] != ["release_id", "source_file"]:
            raise ValueError(
                f"{table} does not exist, or its last two columns are not release_id, source_file"
            )
        n = len(cols) - 2  # number of columns each line of the data file should have
        source_file = os.path.basename(data_path)  # source file name
        cur.execute(
            "select partitioned from user_tables where table_name = upper(:t)",
            t=table,
        )
        if cur.fetchone()[0] == "YES":
            return load_partitioned(
                conn, cur, release_id, table, data_path, cols, n, source_file
            )
        binds = ", ".join(f":{i + 1}" for i in range(n + 2))  # :1, :2, ... placeholders
        # insert statement
        sql = f"insert into {table} ({', '.join(cols)}) values ({binds})"
        # replace only this file of this release
        where = "release_id = :r and source_file = :f"
        cur.execute(f"delete from {table} where {where}", r=release_id, f=source_file)
        print(
            f"{table} {release_id} {source_file}: deleted {cur.rowcount} old rows first"
        )
        rows, batch, errors = 0, [], []  # lines read, current batch, failed rows
        with open(data_path, encoding="utf-8", newline="") as f:  # open the data file
            # line by line
            for row in csv.reader(f, delimiter="|", quoting=csv.QUOTE_NONE):
                rows += 1  # line numbers start at 1
                # column count differs from the table: file and table are different layouts
                if len(row) != n:
                    raise ValueError(
                        f"Line {rows} has {len(row)} columns, {table} needs {n}"
                    )
                # raw values + the two source columns
                batch.append(row + [release_id, source_file])
                if len(batch) == BATCH_SIZE:  # insert once a batch is full
                    errors += insert(cur, sql, batch, rows - len(batch) + 1)
                    batch = []  # empty it and start the next batch
        if batch:  # the last, partial batch must be inserted too
            errors += insert(cur, sql, batch, rows - len(batch) + 1)
        if errors:  # some rows could not be loaded
            conn.rollback()  # undo this delete and insert
            for line, msg in errors[:10]:  # report at most the first 10
                print(f"Line {line} could not be loaded: {msg}", file=sys.stderr)
            raise RuntimeError(
                f"{len(errors)} rows could not be loaded; the whole batch was rolled back"
            )
        if rows == 0:  # empty file
            # error, so an empty file is not mistaken for a successful load
            raise ValueError(f"{data_path} is empty")
        cur.execute(
            f"select count(*) from {table} where {where}", r=release_id, f=source_file
        )
        loaded = cur.fetchone()[0]  # this release's row count in the table
        if loaded != rows:  # does not match the file's row count (reconciliation)
            raise RuntimeError(
                f"File has {rows} rows, table has {loaded}; mismatch, rolled back"
            )
        conn.commit()  # commit only after every check passes
        print(
            f"{table} {release_id} {source_file}: file {rows} rows, table {loaded} rows, match"
        )
        return rows  # return the number of rows loaded


if __name__ == "__main__":  # when this file is run directly
    if len(sys.argv) != 4:  # not exactly 3 arguments
        sys.exit(__doc__)  # print the usage and exit
    load(*sys.argv[1:])  # load
