"""Fail the aggregate check unless required jobs finish as selected."""

import os


def ci_passed(policy_result, scope_result, game_required, smoke_result):
    # scope writes game before its whitespace check, so a failed scope can still say game=false.
    return policy_result == "success" and scope_result == "success" and (
        (game_required == "true" and smoke_result == "success")
        or (game_required == "false" and smoke_result == "skipped")
    )


def main():
    passed = ci_passed(os.environ.get("POLICY_RESULT"),
                       os.environ.get("SCOPE_RESULT"),
                       os.environ.get("GAME_REQUIRED"),
                       os.environ.get("SMOKE_RESULT"))
    print("CI passed." if passed else
          "CI failed: policy and scope must succeed and smoke must match the selected scope.")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
