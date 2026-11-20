"""Check a PR title, or the merge queue commit made from it, against docs/process/git-conventions.md."""
import re
import sys

from check_branch_name import TYPES


# GitHub sets these: the PR author's login, and on the queue commit Dependabot's noreply email, whose
# account ID no one else can claim. A display name ("dependabot[bot]") can be copied by anyone.
DEPENDABOT = {"pr": "dependabot[bot]", "queue": "49699333+dependabot[bot]@users.noreply.github.com"}


def queued_title(message):
    """A squash merge queue commit starts with '<PR title> (#<number>)'."""
    return re.sub(r" \(#[0-9]+\)$", "", message.split("\n", 1)[0])


def check_title(title, dependabot=False):
    if not re.match(rf"^({TYPES})(\([a-z0-9_-]+\))?!?: [a-z]", title):
        raise ValueError(f"PR 제목이 '<type>(<scope>): <소문자 설명>' 형식이 아닙니다: {title!r}\n"
                         f"type: {TYPES}. 예: feat(combat): add initiative turn order. 규칙: docs/process/git-conventions.md")
    # Dependabot names long actions in full, e.g. anthropics/claude-code-action/base-action.
    if len(title) > 72 and not dependabot:
        raise ValueError(f"PR 제목이 72자를 넘습니다 ({len(title)}자).")
    if title.endswith("."):
        raise ValueError("PR 제목 끝에 마침표를 찍지 않습니다.")


def main(argv):
    mode, text, author = argv
    try:
        check_title(queued_title(text) if mode == "queue" else text, author == DEPENDABOT[mode])
    except ValueError as error:
        print(f"::error::{error}".replace("\n", "%0A"))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
