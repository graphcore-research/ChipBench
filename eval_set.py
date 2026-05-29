from pathlib import Path
from typing import Iterable

from ..eval_set import Problem

_BASE_DIR = Path(__file__).parent
_DATASET_DIR = _BASE_DIR / "Verilog Gen"

SYSTEM_PROMPT = """\
You are an expert Verilog hardware designer.

Solve the given Verilog problem.

Return your final answer in a single markdown block formatted with triple backticks followed by the programming language specification.

Generate Verilog that matches the module name, ports, widths, and parameters required by the problem. If the problem provides a module declaration, preserve that interface exactly unless the problem explicitly asks you to change it.
"""


class ChipBenchEvalSetCpu:
    def get_problems(self) -> Iterable[Problem]:
        all_problems_files = _DATASET_DIR.glob("dataset_cpu_ip/problems.txt")
        for problems_file in all_problems_files:
            for line in problems_file.read_text().splitlines():
                problem_name = line.strip()
                if not problem_name:
                    continue

                prompt_file = problems_file.parent / f"{problem_name}_prompt.txt"
                spec = prompt_file.read_text()

                user_prompt = f"""Question:
{spec}

Answer:"""

                yield Problem(
                    eval_set="chipbench_cpu_ip",
                    name=problem_name,
                    system_prompt=SYSTEM_PROMPT,
                    user_prompt=user_prompt,
                )


class ChipBenchEvalSetNoSF:
    def get_problems(self) -> Iterable[Problem]:
        all_problems_files = _DATASET_DIR.glob("dataset_not_self_contain/problems.txt")
        for problems_file in all_problems_files:
            for line in problems_file.read_text().splitlines():
                problem_name = line.strip()
                if not problem_name:
                    continue

                prompt_file = problems_file.parent / f"{problem_name}_prompt.txt"
                spec = prompt_file.read_text()

                user_prompt = f"""Question:
{spec}

Answer:"""

                yield Problem(
                    eval_set="chipbench_not_self_contained",
                    name=problem_name,
                    system_prompt=SYSTEM_PROMPT,
                    user_prompt=user_prompt,
                )


class ChipBenchEvalSetSF:
    def get_problems(self) -> Iterable[Problem]:
        all_problems_files = _DATASET_DIR.glob("dataset_self_contain/problems.txt")
        for problems_file in all_problems_files:
            for line in problems_file.read_text().splitlines():
                problem_name = line.strip()
                if not problem_name:
                    continue

                prompt_file = problems_file.parent / f"{problem_name}_prompt.txt"
                spec = prompt_file.read_text()

                user_prompt = f"""Question:
{spec}

Answer:"""

                yield Problem(
                    eval_set="chipbench_self_contained",
                    name=problem_name,
                    system_prompt=SYSTEM_PROMPT,
                    user_prompt=user_prompt,
                )
