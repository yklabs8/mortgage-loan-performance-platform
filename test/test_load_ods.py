"""Test python/load_ods.py on bad input: it must fail clearly and leave the table as it was before the load.

Usage: .venv/bin/python -m unittest discover -s test -p "test_*.py" (from the repository root)
Each test uses a temporary table ods_zz_load_test (two data columns + release_id + source_file) and temporary files, dropped afterwards.
Cases covered: empty file, missing file, wrong column count, reruns do not double rows,
a bad value in the last batch, an invalid table name, and different files of the same release not affecting each other.
Requires: database started; python/db.py can connect (see Setup in README for the password). Called by: run manually (see Tests in README).
"""

import os  # build paths
import sys  # add python/ to the module search path
import tempfile  # temporary folder
import unittest  # Python's built-in test framework

# Add python/ to the module search path so the module under test can be imported below
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))

import load_ods  # the loader under test (importable only after the path is set above)
from db import connect  # database connection

# temporary table name: must start with ods_ for load_ods to accept it
TABLE = "ods_zz_load_test"


def run_sql(sql, **binds):  # run one statement and commit
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, binds)
        conn.commit()


# row count of the table (optionally for one release only)
def table_rows(release_id=None):
    with connect() as conn, conn.cursor() as cur:
        if release_id is None:
            cur.execute(f"select count(*) from {TABLE}")
        else:
            cur.execute(
                f"select count(*) from {TABLE} where release_id = :r", r=release_id
            )
        return cur.fetchone()[0]


def table_exists():  # whether the temporary table exists right now
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "select count(*) from user_tables where table_name = upper(:t)", t=TABLE
        )
        return cur.fetchone()[0] > 0


class LoadOdsTest(unittest.TestCase):
    def setUp(self):  # before each test: create an empty table and a temporary folder
        self.tmp = tempfile.TemporaryDirectory()  # deleted automatically afterwards
        if table_exists():  # drop a leftover from a previous run first
            run_sql(f"drop table {TABLE} purge")
        run_sql(
            f"create table {TABLE} (c1 varchar2(5), c2 varchar2(5),"
            " release_id varchar2(10) not null, source_file varchar2(100) not null)"
        )

    def tearDown(self):  # after each test: drop the table and the temporary files
        run_sql(f"drop table {TABLE} purge")
        self.tmp.cleanup()

    def write(self, name, lines):  # write a temporary data file and return its path
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write("".join(line + "\n" for line in lines))
        return path

    # normal load; rerunning the same file does not double the rows
    def test_normal_and_rerun_not_doubled(self):
        path = self.write("a.txt", ["x|1", "y|2", "z|3"])
        self.assertEqual(load_ods.load("R99", TABLE, path), 3)
        self.assertEqual(load_ods.load("R99", TABLE, path), 3)
        self.assertEqual(table_rows(), 3)

    # another file of the same release is not affected
    def test_other_file_same_release_kept(self):
        load_ods.load("R99", TABLE, self.write("a.txt", ["x|1", "y|2"]))
        load_ods.load("R99", TABLE, self.write("b.txt", ["z|3"]))
        # reload a.txt, now with 1 row
        load_ods.load("R99", TABLE, self.write("a.txt", ["x|1"]))
        self.assertEqual(table_rows("R99"), 2)  # 1 row from a.txt + 1 row from b.txt

    # empty file: error, old data is kept
    def test_empty_file_fails_and_keeps_old_data(self):
        path = self.write("a.txt", ["x|1", "y|2"])
        load_ods.load("R99", TABLE, path)
        self.write("a.txt", [])  # the same file is now empty
        with self.assertRaises(ValueError):
            load_ods.load("R99", TABLE, path)
        self.assertEqual(table_rows(), 2)  # the delete was rolled back

    def test_missing_file_fails(self):  # missing file: error, nothing in the table
        with self.assertRaises(FileNotFoundError):
            load_ods.load("R99", TABLE, os.path.join(self.tmp.name, "none.txt"))
        self.assertEqual(table_rows(), 0)

    # line 3 has the wrong column count: error, no rows kept
    def test_wrong_column_count_fails(self):
        path = self.write("a.txt", ["x|1", "y|2", "z|3|extra"])
        with self.assertRaisesRegex(ValueError, "Line 3 "):
            load_ods.load("R99", TABLE, path)
        self.assertEqual(table_rows(), 0)

    # a value too long in the last batch: error, whole batch rolled back
    def test_bad_value_in_last_batch_fails(self):
        original = load_ods.BATCH_SIZE
        load_ods.BATCH_SIZE = 2  # 2 rows per batch, so line 5 falls into the last batch
        try:
            path = self.write("a.txt", ["a|1", "b|2", "c|3", "d|4", "toolong|5"])
            with self.assertRaisesRegex(RuntimeError, "could not be loaded"):
                load_ods.load("R99", TABLE, path)
        finally:
            load_ods.BATCH_SIZE = original
        self.assertEqual(table_rows(), 0)

    # table name does not start with ods_: error, no other table is touched
    def test_bad_table_name_fails(self):
        path = self.write("a.txt", ["x|1"])
        with self.assertRaises(ValueError):
            load_ods.load("R99", "dim_loan", path)


if __name__ == "__main__":
    unittest.main()
