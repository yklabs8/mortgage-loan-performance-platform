"""Verify ODS file exchange, reruns, and the cross-file primary key on a small partitioned Oracle table."""

import os
import sys
import tempfile
import unittest

import oracledb

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))

import load_ods
from db import connect

TABLE = "ods_zz_exchange"
STAGE = f"{TABLE}_stage"


def execute(sql, **binds):
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, binds)
        conn.commit()


def rows():
    with connect() as conn, conn.cursor() as cur:
        cur.execute(f"select c1, source_file from {TABLE} order by c1")
        return cur.fetchall()


class LoadOdsExchangeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
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

    def tearDown(self):
        execute(f"drop table {STAGE} purge")
        execute(f"drop table {TABLE} purge")
        self.tmp.cleanup()

    def write(self, name, lines):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as stream:
            stream.write("".join(line + "\n" for line in lines))
        return path

    def test_replace_one_file_keeps_other_and_global_pk(self):
        a = self.write("a.txt", ["a|1", "b|2"])
        b = self.write("b.txt", ["c|3"])
        self.assertEqual(load_ods.load("R99", TABLE, a), 2)
        self.assertEqual(load_ods.load("R99", TABLE, b), 1)
        self.assertEqual(load_ods.load("R99", TABLE, self.write("a.txt", ["a|4"])), 1)
        self.assertEqual(rows(), [("a", "a.txt"), ("c", "b.txt")])
        self.assertEqual(load_ods.load("R99", TABLE, a), 1)
        self.assertEqual(rows(), [("a", "a.txt"), ("c", "b.txt")])

    def test_duplicate_in_other_file_rejected_without_losing_old_data(self):
        load_ods.load("R99", TABLE, self.write("a.txt", ["a|1"]))
        with self.assertRaises(oracledb.DatabaseError) as caught:
            load_ods.load("R99", TABLE, self.write("b.txt", ["a|2"]))
        self.assertIn("ORA-00001", str(caught.exception))
        self.assertEqual(rows(), [("a", "a.txt")])
        with connect() as conn, conn.cursor() as cur:
            cur.execute(f"select count(*) from {STAGE}")
            self.assertEqual(cur.fetchone()[0], 1)

    def test_bad_file_preserves_partition_and_clears_uncommitted_stage(self):
        path = self.write("a.txt", ["a|1"])
        load_ods.load("R99", TABLE, path)
        with self.assertRaisesRegex(ValueError, "Line 2 "):
            load_ods.load("R99", TABLE, self.write("a.txt", ["b|2", "bad|3|4"]))
        self.assertEqual(rows(), [("a", "a.txt")])
        with connect() as conn, conn.cursor() as cur:
            cur.execute(f"select count(*) from {STAGE}")
            self.assertEqual(cur.fetchone()[0], 0)

    def test_interrupted_swap_keeps_old_segment_for_reverse_exchange(self):
        load_ods.load("R99", TABLE, self.write("a.txt", ["a|1"]))
        with connect() as conn, conn.cursor() as cur:
            cur.execute(
                "select partition_name from user_tab_partitions"
                " where table_name = upper(:t) and partition_name != 'P_DEFAULT'",
                t=TABLE,
            )
            partition = cur.fetchone()[0]
        execute(
            f"insert into {STAGE} (c1,c2,release_id,source_file)"
            " values ('b','2','R99','a.txt')"
        )
        swap = (
            f"alter table {TABLE} exchange partition {partition} with table {STAGE}"
            " excluding indexes with validation update global indexes"
        )
        execute(swap)
        self.assertEqual(rows(), [("b", "a.txt")])
        with connect() as conn, conn.cursor() as cur:
            cur.execute(f"select c1 from {STAGE}")
            self.assertEqual(cur.fetchone()[0], "a")
        execute("alter index ods_zz_exchange_stage_pk rebuild")
        execute(swap)
        self.assertEqual(rows(), [("a", "a.txt")])
        execute(f"truncate table {STAGE}")
        execute("alter index ods_zz_exchange_stage_pk rebuild")


if __name__ == "__main__":
    unittest.main()
