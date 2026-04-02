import re
import tempfile
from pathlib import Path

from ..async_util import run_with_timeout
from ..evaluator import EvalResult, Sample

_THIS_DIR = Path(__file__).parent
_DATASET_DIR = _THIS_DIR / "Verilog Gen"

# Build lookup table: problem name -> problem directory
_PROBLEMS: dict[str, Path] = {}
for test_file in _DATASET_DIR.glob("**/*_test.sv"):
    # Extract problem name from e.g. "Prob001_zero_test.sv" -> "Prob001_zero"
    problem_name = test_file.name.removesuffix("_test.sv")
    _PROBLEMS[problem_name] = test_file.parent


async def evaluate(sample: Sample) -> EvalResult:
    if sample.problem not in _PROBLEMS:
        raise ValueError(f"Unknown problem: {sample.problem}")

    # Extract code from between [BEGIN] and [DONE] markers if present
    code = sample.code
    marker_pairs = [
        ("[BEGIN]", "[DONE]"),
        ("[BEGIN]", "[END]"),
        ("[ BEGIN ]", "[ DONE ]"),
        ("[ BEGIN ]", "[ END ]"),
    ]
    for begin_marker, end_marker in marker_pairs:
        if begin_marker in code and end_marker in code:
            code = code.split(begin_marker, 1)[1].split(end_marker, 1)[0].strip()
            break

    if "```verilog" in code or "```systemverilog" in code or "```" in code:
        # Find the first verilog code block
        for fence in ["```verilog", "```systemverilog", "```"]:
            if fence in code:
                # Split at the opening fence
                parts = code.split(fence, 1)
                if len(parts) >= 2:
                    # Everything after the opening fence
                    after_fence = parts[1]
                    # Remove leading language tag line if present
                    if after_fence.startswith("\n"):
                        after_fence = after_fence[1:]
                    if after_fence.startswith("verilog\n"):
                        after_fence = after_fence[len("verilog\n") :]
                    elif after_fence.startswith("systemverilog\n"):
                        after_fence = after_fence[len("systemverilog\n") :]

                    # Find the closing fence
                    if "```" in after_fence:
                        code = after_fence.split("```", 1)[0].strip()
                        break

    # Fallback: if no markers were used, try extracting module...endmodule blocks
    # instead of compiling raw full text
    if "module" in code and "endmodule" in code:
        module_blocks = re.findall(r"\bmodule\b[\s\S]*?\bendmodule\b", code)
        if module_blocks:
            code = "\n\n".join(block.strip() for block in module_blocks).strip()

    problem_dir = _PROBLEMS[sample.problem]
    test_file = problem_dir / f"{sample.problem}_test.sv"
    ref_file = problem_dir / f"{sample.problem}_ref.sv"
    log_parts = []

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Write the sample code
        sample_file = tmp_dir / "sample.sv"
        sample_file.write_text(code)

        # Compile with iverilog
        compile_cmd = [
            "iverilog",
            "-Wall",
            "-Winfloop",
            "-Wno-timescale",
            "-g2012",
            "-s",
            "tb",
            "-o",
            "test.vvp",
            str(test_file),
            str(ref_file),
            str(sample_file),
        ]
        completed, compile_output = await run_with_timeout(
            compile_cmd, timeout=30, cwd=tmp_dir
        )
        log_parts.append(f"=== compile ===\n{compile_output}")

        if not completed:
            return EvalResult(
                passed=False,
                details={"reason": "compile timeout", "log": "\n\n".join(log_parts)},
            )

        vvp_file = tmp_dir / "test.vvp"
        if not vvp_file.exists():
            return EvalResult(
                passed=False,
                details={"reason": "compile error", "log": "\n\n".join(log_parts)},
            )

        # Simulate with vvp (longer timeout since testbench has internal timeout)
        completed, sim_output = await run_with_timeout(
            "./test.vvp", timeout=60, cwd=tmp_dir
        )
        log_parts.append(f"=== simulate ===\n{sim_output}")

        if not completed or "TIMEOUT" in sim_output:
            return EvalResult(
                passed=False,
                details={"reason": "simulation timeout", "log": "\n\n".join(log_parts)},
            )

        # Parse simulation output
        match = re.search(
            r"(?:Mismatches:\s*(?P<m1>\d+)\s*in\s*(?P<t1>\d+)\s*samples)"
            r"|(?:Total\s+mismatched\s+samples\s+is\s*(?P<m2>\d+)\s*out\s+of\s*(?P<t2>\d+)\s*samples\.?)"
            r"|(?P<no_mismatch>(?:Hint:\s*)?No\s+mismatched\s+samples\.?)",
            sim_output,
            flags=re.IGNORECASE,
        )

        if match:
            if match.group("no_mismatch"):
                mismatches = 0
                total = 0
            else:
                mismatches = int(match.group("m1") or match.group("m2"))
                total = int(match.group("t1") or match.group("t2"))
            passed = mismatches == 0
            reason = "passed" if passed else f"{mismatches}/{total} mismatches"
        else:
            reason = "output not matched"
            passed = False

        return EvalResult(
            passed=passed,
            details={"reason": reason, "log": "\n\n".join(log_parts)},
        )
