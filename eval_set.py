from pathlib import Path
from typing import Iterable

from ..eval_set import Problem

_BASE_DIR = Path(__file__).parent
_DATASET_DIR = _BASE_DIR / "Verilog Gen"

SYSTEM_PROMPT = (
    "You are a Verilog RTL designer that only writes code using correct Verilog syntax."
)


class ChipBenchEvalSet:
    def get_problems(self) -> Iterable[Problem]:
        all_problems_files = _DATASET_DIR.glob("**/problems.txt")
        for problems_file in all_problems_files:
            for line in problems_file.read_text().splitlines():
                problem_name = line.strip()
                if not problem_name:
                    continue

                prompt_file = problems_file.parent / f"{problem_name}_prompt.txt"
                spec = prompt_file.read_text()

                user_prompt = f"""Question:
    {spec}

    Enclose your code with [BEGIN] and [DONE]. Only output the code snippet and do NOT output anything else.

    Answer:"""

                yield Problem(
                    eval_set="chipbench",
                    name=problem_name,
                    system_prompt=SYSTEM_PROMPT,
                    user_prompt=user_prompt,
                )
