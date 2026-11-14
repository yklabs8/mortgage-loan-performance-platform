"""Fixed exit codes when platform programs fail; a scheduler decides whether to retry by exit code, not by guessing from error text.

42 data or quality failure, 43 publication state unknown, 44 privilege, 45 space guard or 20-copy limit, 75 transient connection failure (the only one retried).
"""

DATA = 42
PUBLISH_UNKNOWN = 43
PERMISSION = 44
SPACE = 45
TRANSIENT = 75
KNOWN = {DATA, PUBLISH_UNKNOWN, PERMISSION, SPACE, TRANSIENT}


class SpaceGuardError(ValueError):
    """Space guard or budget triggered: stop without retry, exit 45."""

    exit_code = SPACE


def exit_code(error):
    """Map a ValueError raised by the platform to an exit code: space guard 45, everything else data or argument error 42."""
    return getattr(error, "exit_code", DATA)
