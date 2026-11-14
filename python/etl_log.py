"""Pipeline run log: write each run and each step's start, end, row count, and success or failure into etl_run / etl_run_step.

Usage (arguments in order):
  python python/etl_log.py start <pipeline> <args...>                 create a run and print its run ID
  python python/etl_log.py step-start <run ID> <step no> <step name> <log file>
  python python/etl_log.py step-end <run ID> <step no> <SUCCESS|FAILED|SKIPPED> <exit code>
  python python/etl_log.py end <run ID> <SUCCESS|FAILED>
  python python/etl_log.py resume-point <pipeline> <args...>          if the previous run with the same arguments failed, print the failed step name
Step names look like R45:load_ods (release:step). On success a row count is queried per step (see ROW_SQL); on failure the last 20 log lines are stored.
Each step's result is committed at once, so if a pipeline fails midway the earlier step records remain.
Requires: python/db.py; source/ops/etl_run_tables.sql has run. Called by: pipeline scripts and the steps in docs/setup.md.
"""

import sys  # read command-line arguments
from collections import deque  # keep only the end of the log, so a large log never fills memory

from db import connect  # database connection

TAIL_LINES = 20  # log lines stored on failure (platform convention)
TAIL_BYTES = 3900  # error_tail is varchar2(4000 BYTE); leave margin for UTF-8 bytes

# How each kind of step counts "rows processed" after success (:r is the release); steps not listed record no row count
ROW_SQL = {
    # ODS: total rows of this release in the ODS tables
    "load_ods": """
        select sum(n) from (
           select count(*) as n from ods_orig where release_id = :r
           union all select count(*) from ods_perf where release_id = :r
           union all select count(*) from ods_orig_pre202607 where release_id = :r
           union all select count(*) from ods_perf_pre202607 where release_id = :r
        )""",
    # Warehouse: monthly detail rows of this release (partitioned by release, reads one partition)
    "load_dw": "select count(*) from dwd_loan_monthly_perf where release_id = :r",
    # Incremental extraction: case rows read by the latest extraction
    "cdc_review": """
        select extracted_rows from etl_cdc_run
        where source_name = 'REVIEW_CASE'
        order by run_id desc fetch first 1 row only""",
}


def start(pipeline, args):
    with connect() as conn, conn.cursor() as cur:
        run_id = cur.var(int)
        cur.execute(
            "insert into etl_run (pipeline, run_args, status) values (:p, :a, 'RUNNING')"
            " returning run_id into :id",
            p=pipeline,
            a=" ".join(args),
            id=run_id,
        )
        conn.commit()
        print(run_id.getvalue()[0])


def step_start(run_id, step_no, step_name, log_file):
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "insert into etl_run_step (run_id, step_no, step_name, status, log_file)"
            " values (:id, :n, :s, 'RUNNING', :f)",
            id=int(run_id),
            n=int(step_no),
            s=step_name,
            f=log_file,
        )
        conn.commit()


def log_tail(log_file):
    """Last TAIL_LINES lines of the log file; empty if the file does not exist."""
    try:
        with open(log_file, encoding="utf-8", errors="replace") as f:
            lines = deque(f, maxlen=TAIL_LINES)
    except FileNotFoundError:
        return None
    tail = "".join(lines).rstrip("\r\n").encode("utf-8")
    # The cut may fall inside a multi-byte character; drop only the incomplete leading character.
    return tail[-TAIL_BYTES:].decode("utf-8", errors="ignore")


def step_end(run_id, step_no, status, exit_code):
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "select step_name, log_file from etl_run_step where run_id = :id and step_no = :n",
            id=int(run_id),
            n=int(step_no),
        )
        step_name, log_file = cur.fetchone()
        release_id, step = step_name.split(":", 1)
        rows = None
        if status == "SUCCESS" and step in ROW_SQL:
            cur.execute(
                ROW_SQL[step], {"r": release_id} if ":r" in ROW_SQL[step] else {}
            )
            rows = cur.fetchone()[0]
        tail = log_tail(log_file) if status == "FAILED" else None
        cur.execute(
            "update etl_run_step set status = :st, ended_at = systimestamp,"
            " processed_rows = :n_rows, exit_code = :ec, error_tail = :tail"
            " where run_id = :id and step_no = :n",
            st=status,
            n_rows=rows,
            ec=int(exit_code),
            tail=tail,
            id=int(run_id),
            n=int(step_no),
        )
        conn.commit()


def end(run_id, status):
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "update etl_run set status = :st, ended_at = systimestamp where run_id = :id",
            st=status,
            id=int(run_id),
        )
        conn.commit()


def resume_point(pipeline, args):
    """Previous run with the same arguments: print the failed step if it failed; print nothing if it succeeded or there is none."""
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            """
            select s.step_name
            from etl_run r
            inner join etl_run_step s on r.run_id = s.run_id
            where r.run_id = (
               select max(run_id) from etl_run where pipeline = :p and run_args = :a
            )
               and r.status = 'FAILED' and s.status = 'FAILED'
            """,
            p=pipeline,
            a=" ".join(args),
        )
        row = cur.fetchone()
        if row:
            print(row[0])


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd, rest = argv[1], argv[2:]
    if cmd == "start" and len(rest) >= 2:
        start(rest[0], rest[1:])
    elif cmd == "step-start" and len(rest) == 4:
        step_start(*rest)
    elif (
        cmd == "step-end"
        and len(rest) == 4
        and rest[2] in ("SUCCESS", "FAILED", "SKIPPED")
    ):
        step_end(*rest)
    elif cmd == "end" and len(rest) == 2 and rest[1] in ("SUCCESS", "FAILED"):
        end(*rest)
    elif cmd == "resume-point" and len(rest) >= 2:
        resume_point(rest[0], rest[1:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
