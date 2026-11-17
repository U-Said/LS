/* Runs the detector self-test from the command line: coretest  → report, exit code = failures. */
#include <stdio.h>
#include "ls_core.h"

int main(void)
{
    static char report[16384];
    int fails = ls_selftest(report, (int)sizeof report);
    fputs(report, stdout);
    printf("%d failed\n", fails);
    return fails;
}
