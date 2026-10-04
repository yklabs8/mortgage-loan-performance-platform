"""Add column names to a Freddie sample, count rows and loans, and check that orig and perf match on loan number.

Usage: python profile_sample.py <orig data> <orig header> <perf data> <perf header>
Data and header files must come from the same release. Standard library only; no other script calls it yet.
"""

import csv  # standard library: split each line on the delimiter
import sys  # standard library: read command-line arguments


# name the columns from the header, check each line, return row count and loan numbers
def scan(data_path, header_path):
    with open(header_path, encoding="utf-8") as f:  # open the official header file
        # read the first line and split it on | into column names
        header = f.readline().rstrip("\r\n").split("|")
    # position of the loan number; error if absent
    col = header.index("LOAN IDENTIFIER")
    rows, loans = 0, set()  # row count, set of loan numbers
    # newline="" is the open mode the csv module requires; QUOTE_NONE: quotes are ordinary characters, columns are never merged
    with open(data_path, encoding="utf-8", newline="") as f:  # open the data file
        for row in csv.reader(f, delimiter="|", quoting=csv.QUOTE_NONE):  # line by line
            where = f"{data_path} line {rows + 1}"  # location reported on error
            # this line has a different column count from the header
            if len(row) != len(header):
                raise ValueError(
                    f"{where} has {len(row)} columns, header has {len(header)}"
                )
            if not row[col].strip():  # empty loan number
                raise ValueError(f"{where} has an empty loan number")  # error
            if rows == 0:  # first line
                # print "column: value" for a visual check
                print(dict(zip(header, row)))
            rows += 1  # one more row
            loans.add(row[col])  # remember the loan number
    if rows == 0:  # no line was read at all
        # error, so an empty file is not mistaken for a full match
        raise ValueError(f"{data_path} is empty")
    return rows, loans  # return the result


if len(sys.argv) != 5:  # not exactly 4 arguments
    sys.exit(__doc__)  # print the usage above and exit
orig, orig_hdr, perf, perf_hdr = sys.argv[1:]  # the 4 paths come from the command line
o_rows, o_loans = scan(orig, orig_hdr)  # scan orig
p_rows, p_loans = scan(perf, perf_hdr)  # scan perf
if o_rows != len(o_loans):  # orig must have exactly one row per loan
    raise ValueError(
        f"orig has duplicate loan numbers: {o_rows} rows, {len(o_loans)} loans"
    )
print(f"orig: {o_rows} rows, {len(o_loans)} loans")  # orig result
print(f"perf: {p_rows} rows, {len(p_loans)} loans")  # perf result
print(f"loans in perf but not in orig: {len(p_loans - o_loans)}")  # mismatch (1)
print(f"loans in orig but not in perf: {len(o_loans - p_loans)}")  # mismatch (2)
