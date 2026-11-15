"""Verify external loading, partition exchange and all file layouts in TEST; clean only test-owned objects."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import oracledb

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from database_target import settings
from db import connect_test_database as connect

ROOT = Path(__file__).resolve().parents[1]
TABLE = "ods_zz_exchange"
STAGE = TABLE + "_stage"


def execute(sql, **binds):
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, binds)
        conn.commit()


def rows():
    with connect() as conn, conn.cursor() as cur:
        cur.execute(f"select c1, c2, source_file from {TABLE} order by c1")
        return cur.fetchall()


def setUpModule():
    connect().close()  # Check the database marker before creating tables, writing files or cleaning objects.


class ExternalLoadTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.container = settings()[1]
        self.files = set()
        execute(
            f"create table {TABLE} (c1 varchar2(5), c2 varchar2(5),"
            " release_id varchar2(10) not null, source_file varchar2(100) not null,"
            " constraint ods_zz_exchange_pk primary key (release_id, c1))"
            " partition by list (release_id, source_file)"
            " (partition p_default values (default))"
        )
        execute(f"create table {STAGE} for exchange with table {TABLE}")
        execute(
            f"alter table {STAGE} add constraint ods_zz_exchange_stage_pk"
            " primary key (release_id, c1)"
        )
        execute(
            f"create table ext_{TABLE} (c1 varchar2(5), c2 varchar2(5))"
            " organization external (type oracle_loader default directory ods_ext_dir"
            " access parameters (records delimited by newline characterset al32utf8"
            " nologfile nobadfile nodiscardfile fields terminated by '|' notrim"
            " missing field values are null) location ('placeholder.txt')) reject limit 0"
        )

    def tearDown(self):
        for table in ("ext_" + TABLE, STAGE, TABLE):
            execute(f"drop table {table} purge")
        for name in self.files:
            subprocess.run(
                [
                    "docker",
                    "exec",
                    self.container,
                    "rm",
                    "-f",
                    "/opt/oracle/ext_data/" + name,
                ],
                check=True,
                capture_output=True,
            )
        self.tmp.cleanup()

    def write(self, name, lines):
        name = "zz_ext_" + name
        path = Path(self.tmp.name) / name
        path.write_text("".join(line + "\n" for line in lines))
        self.files.add(name)
        subprocess.run(
            [
                "docker",
                "cp",
                str(path),
                self.container + ":/opt/oracle/ext_data/" + name,
            ],
            check=True,
            capture_output=True,
        )
        return name

    def load(self, name, table=TABLE, release="R99"):
        with connect() as conn, conn.cursor() as cur:
            cur.callproc("load_ods_from_ext", [release, table, name])

    def stage_rows(self):
        with connect() as conn, conn.cursor() as cur:
            cur.execute(f"select count(*) from {STAGE}")
            return cur.fetchone()[0]

    def fingerprint(self, name):
        with connect() as conn, conn.cursor() as cur:
            return cur.callfunc("ods_file_hash", str, [TABLE, "R99", name])

    def test_normal_and_rerun_not_doubled(self):
        name = self.write("a.txt", ["x|1", "y|2", "z|3"])
        self.load(name)
        before = self.fingerprint(name)
        self.load(name)
        self.assertEqual(len(rows()), 3)
        self.assertEqual(self.fingerprint(name), before)

    def test_other_file_same_release_kept(self):
        self.load(self.write("a.txt", ["a|1", "b|2"]))
        self.load(self.write("b.txt", ["c|3"]))
        self.load(self.write("a.txt", ["a|4"]))
        expected = [("a", "4", "zz_ext_a.txt"), ("c", "3", "zz_ext_b.txt")]
        self.assertEqual(rows(), expected)
        self.load("zz_ext_a.txt")
        self.assertEqual(rows(), expected)

    def test_empty_file_fails_and_keeps_old_data(self):
        self.load(self.write("a.txt", ["a|1", "b|2"]))
        before = rows()
        with self.assertRaisesRegex(oracledb.DatabaseError, "ORA-20024"):
            self.load(self.write("a.txt", []))
        self.assertEqual(rows(), before)
        self.assertEqual(self.stage_rows(), 0)

    def test_missing_file_fails(self):
        with self.assertRaises(oracledb.DatabaseError):
            self.load("zz_ext_missing.txt")
        self.assertEqual(rows(), [])
        result = subprocess.run(
            [
                "bash",
                "scripts/4_load_ods_ext.sh",
                "R99",
                TABLE,
                self.tmp.name + "/none.txt",
            ],
            check=False,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("File not found", result.stderr)

    def test_wrong_column_count_fails(self):
        for bad in ("z|3|extra", "z", ""):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(oracledb.DatabaseError, "ORA-20025"):
                    self.load(self.write("a.txt", ["x|1", "y|2", bad]))
                self.assertEqual(rows(), [])
                self.assertEqual(self.stage_rows(), 0)

    def test_bad_value_at_end_fails(self):
        with self.assertRaises(oracledb.DatabaseError):
            self.load(self.write("a.txt", ["a|1", "b|2", "c|3", "d|4", "toolong|5"]))
        self.assertEqual(rows(), [])
        self.assertEqual(self.stage_rows(), 0)

    def test_bad_table_name_fails(self):
        name = self.write("a.txt", ["x|1"])
        for table in (
            "dim_loan",
            "ods_missing",
            "ods_x;drop table x",
            "ods_load_event",
        ):
            with (
                self.subTest(table=table),
                self.assertRaisesRegex(oracledb.DatabaseError, "ORA-20021"),
            ):
                self.load(name, table=table)
        self.assertEqual(rows(), [])

    def test_bad_release_and_filename_rejected(self):
        with self.assertRaisesRegex(oracledb.DatabaseError, "ORA-20022"):
            self.load("../a.txt")
        with self.assertRaisesRegex(oracledb.DatabaseError, "ORA-20023"):
            self.load("a.txt", release="R99'")

    def test_duplicate_in_other_file_rejected_without_losing_old_data(self):
        self.load(self.write("a.txt", ["a|1"]))
        with self.assertRaisesRegex(oracledb.DatabaseError, "ORA-00001"):
            self.load(self.write("b.txt", ["a|2"]))
        self.assertEqual(rows(), [("a", "1", "zz_ext_a.txt")])
        self.assertEqual(self.stage_rows(), 1)

    def test_bad_file_preserves_partition_and_clears_uncommitted_stage(self):
        self.load(self.write("a.txt", ["a|1"]))
        for bad in (["b|2", "bad|3|4"], ["b|2", "toolong|3"]):
            with self.subTest(bad=bad):
                with self.assertRaises(oracledb.DatabaseError):
                    self.load(self.write("a.txt", bad))
                self.assertEqual(rows(), [("a", "1", "zz_ext_a.txt")])
                self.assertEqual(self.stage_rows(), 0)

    def test_nonempty_stage_rejected_without_changing_partition(self):
        self.load(self.write("a.txt", ["a|1"]))
        execute(
            f"insert into {STAGE} (c1,c2,release_id,source_file) values ('b','2','R99','a.txt')"
        )
        with self.assertRaisesRegex(oracledb.DatabaseError, "ORA-20027"):
            self.load(self.write("a.txt", ["c|3"]))
        self.assertEqual(rows(), [("a", "1", "zz_ext_a.txt")])
        self.assertEqual(self.stage_rows(), 1)

    def test_interrupted_swap_keeps_old_segment_for_reverse_exchange(self):
        self.load(self.write("a.txt", ["a|1"]))
        with connect() as conn, conn.cursor() as cur:
            cur.execute(
                "select partition_name from user_tab_partitions where table_name=upper(:t) and partition_name!='P_DEFAULT'",
                t=TABLE,
            )
            partition = cur.fetchone()[0]
        execute(
            f"insert into {STAGE} (c1,c2,release_id,source_file) values ('b','2','R99','zz_ext_a.txt')"
        )
        swap = f"alter table {TABLE} exchange partition {partition} with table {STAGE} excluding indexes with validation update global indexes"
        execute(swap)
        self.assertEqual(rows(), [("b", "2", "zz_ext_a.txt")])
        with connect() as conn, conn.cursor() as cur:
            cur.execute(f"select c1 from {STAGE}")
            self.assertEqual(cur.fetchone()[0], "a")
        execute("alter index ods_zz_exchange_stage_pk rebuild")
        execute(swap)
        self.assertEqual(rows(), [("a", "1", "zz_ext_a.txt")])
        execute(f"truncate table {STAGE}")
        execute("alter index ods_zz_exchange_stage_pk rebuild")


class ExternalLayoutTest(unittest.TestCase):
    def test_all_layouts_match_and_load(self):
        tables = (
            "ods_orig",
            "ods_perf",
            "ods_orig_pre202607",
            "ods_perf_pre202607",
        )
        container = settings()[1]
        for table in tables:
            with (
                self.subTest(table=table),
                tempfile.TemporaryDirectory() as tmp,
                connect() as conn,
                conn.cursor() as cur,
            ):

                def columns(name):
                    cur.execute(
                        "select column_name,data_type,data_length from user_tab_columns where table_name=upper(:t) order by column_id",
                        t=name,
                    )
                    return cur.fetchall()

                cols = columns(table)[:-2]
                self.assertEqual(columns("ext_" + table), cols)
                cur.execute(
                    "select column_name from user_part_key_columns where name=upper(:t) order by column_position",
                    t=table,
                )
                self.assertEqual(cur.fetchall(), [("RELEASE_ID",), ("SOURCE_FILE",)])
                # Preserve text, nulls and surrounding spaces in every column; use short text for primary keys.
                values = ["1"] * len(cols)
                values[-1] = ""
                values[0] = " 1 " if cols[0][2] >= 3 else "1"
                name = "zz_ext_" + table + ".txt"
                path = Path(tmp) / name
                path.write_text("|".join(values) + "\n")
                subprocess.run(
                    [
                        "docker",
                        "cp",
                        str(path),
                        container + ":/opt/oracle/ext_data/" + name,
                    ],
                    check=True,
                    capture_output=True,
                )
                try:
                    cur.callproc("load_ods_from_ext", ["ZZ_EXT", table, name])
                    names = ",".join(c[0] for c in cols)
                    cur.execute(
                        f"select {names} from {table} where release_id='ZZ_EXT' and source_file=:f",
                        f=name,
                    )
                    self.assertEqual(cur.fetchall(), [tuple(v or None for v in values)])
                finally:
                    # Delete only partitions and ledger entries created by this test.
                    cur.execute(
                        "select 'P_' || substr(rawtohex(standard_hash('ZZ_EXT' || chr(0) || :f, 'SHA256')),1,24) from dual",
                        f=name,
                    )
                    part = cur.fetchone()[0]
                    cur.execute(
                        "select count(*) from user_tab_partitions where table_name=upper(:t) and partition_name=:p",
                        t=table,
                        p=part,
                    )
                    if cur.fetchone()[0]:
                        cur.execute(
                            f"alter table {table} drop partition {part} update global indexes"
                        )
                    cur.execute(
                        "delete from ods_load_event where release_id='ZZ_EXT' and source_table=:t and source_file=:f",
                        t=table,
                        f=name,
                    )
                    conn.commit()
                    subprocess.run(
                        [
                            "docker",
                            "exec",
                            container,
                            "rm",
                            "-f",
                            "/opt/oracle/ext_data/" + name,
                        ],
                        check=True,
                        capture_output=True,
                    )
