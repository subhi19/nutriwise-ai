"""
convert_to_relative_imports.py

Fixes:  ModuleNotFoundError: No module named 'nutrition_repo'
which happens when the backend imports ai_services as a package.

Put this file in the ai-services/ folder (the one that CONTAINS the
ai_services/ folder), then run from there:

    python convert_to_relative_imports.py            # PREVIEW only, changes nothing
    python convert_to_relative_imports.py --apply    # make the changes (keeps .bak copies)

What it changes
  1. Files INSIDE ai_services/ (the package):
         from nutrition_repo import search_food
      -> from .nutrition_repo import search_food

  2. Test and script files OUTSIDE the package (tests/, scripts/, test_*.py):
         from nutrition_repo import search_food
      -> from ai_services.nutrition_repo import search_food
     and their sys.path line is pointed at the folder that contains ai_services/.

It only touches import lines (and those sys.path lines). It is safe to run
twice: files that are already converted are left alone.

AFTER running with --apply, commit to git, and run modules like this from
the ai-services/ folder (plain `python meal_analyzer.py` no longer works,
because relative imports need the package):

    python -m ai_services.meal_analyzer
    python -m ai_services.recipes
"""

import difflib
import re
import sys
import py_compile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PKG = ROOT / "ai_services"
APPLY = "--apply" in sys.argv

if not PKG.is_dir():
    sys.exit(f"Could not find the folder: {PKG}\n"
             "Run this from the ai-services/ folder (the one that contains ai_services/).")

# ---- which files are part of the package, and which are outside scripts ----
package_files = sorted(
    p for p in PKG.glob("*.py") if not p.name.startswith("test_")
)
module_names = sorted(p.stem for p in package_files if p.name != "__init__.py")

outside_files = []
for folder in ("tests", "scripts"):
    d = ROOT / folder
    if d.is_dir():
        outside_files += sorted(d.glob("*.py"))
outside_files += sorted(PKG.glob("test_*.py"))   # a test someone left inside the package folder
outside_files += sorted(ROOT.glob("test_*.py"))  # a test next to this script

names = "|".join(re.escape(n) for n in module_names)
BARE_FROM = re.compile(rf"^([ \t]*)from ({names}) import ", re.M)
BARE_PLAIN = re.compile(rf"^[ \t]*import ({names})\b", re.M)
PATH_TO_PKG = re.compile(
    r'os\.path\.join\((os\.path\.dirname\(__file__\)|_here), "\.\.", "ai_services"\)')
PATH_HERE_LINE = re.compile(r"^sys\.path\.insert\(0, _here\)[ \t]*\n", re.M)

ROOT_PATH_LINE = (
    'sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))'
    "  # the folder that contains ai_services/\n"
)


def convert_package_file(text: str) -> str:
    return BARE_FROM.sub(r"\1from .\2 import ", text)


def has_root_path_line(text: str) -> bool:
    for line in text.splitlines():
        code = line.split("#", 1)[0].strip()   # ignore the trailing comment
        if code.startswith("sys.path.insert") and '".."' in code and "ai_services" not in code:
            return True
    return False


def convert_outside_file(text: str, path: Path) -> str:
    new = BARE_FROM.sub(r"\1from ai_services.\2 import ", text)
    new = PATH_TO_PKG.sub(r'os.path.join(\1, "..")', new)
    new = PATH_HERE_LINE.sub("", new)

    # If the file now imports ai_services but never puts the right folder on
    # sys.path, add that line just before the first such import.
    needs_path = path.parent != ROOT
    if needs_path and "from ai_services." in new and not has_root_path_line(new):
        m = re.search(r"^from ai_services\.", new, re.M)
        inject = "import os\nimport sys\n" + ROOT_PATH_LINE + "\n"
        new = new[:m.start()] + inject + new[m.start():]
    return new


def show_diff(old: str, new: str):
    """Prints a compact diff: lines starting with - are removed, + are added."""
    diff = difflib.unified_diff(old.splitlines(), new.splitlines(), lineterm="", n=0)
    for line in diff:
        if line.startswith(("---", "+++")):
            continue
        if line.startswith("@@"):
            print(f"   {line}")          # e.g. @@ -19 +19 @@  = around line 19 of the old file
        else:
            print(f"     {line}")


def process(path: Path, converter):
    old = path.read_text(encoding="utf-8")
    new = converter(old)
    warnings = []
    if BARE_PLAIN.search(old):
        warnings.append("has a plain `import <module>` line — change that one by hand")
    if "except ImportError" in old:
        warnings.append("has an `except ImportError` block — review its imports by hand")
    return old, new, warnings


def main():
    mode = "APPLYING CHANGES" if APPLY else "PREVIEW ONLY (nothing is written). Add --apply to make the changes."
    print(f"\n{mode}\nPackage folder: {PKG}\n")

    jobs = [(p, convert_package_file, "package") for p in package_files]
    jobs += [(p, lambda t, p=p: convert_outside_file(t, p), "outside") for p in outside_files]

    changed, warned = [], []
    for path, converter, kind in jobs:
        old, new, warnings = process(path, converter)
        rel = path.relative_to(ROOT)
        if new != old:
            changed.append(path)
            print(f"[{kind}] {rel}")
            show_diff(old, new)
            if APPLY:
                bak = path.with_suffix(path.suffix + ".bak")
                if not bak.exists():          # keep the FIRST backup: it is your true original
                    bak.write_text(old, encoding="utf-8")
                path.write_text(new, encoding="utf-8")
        for w in warnings:
            warned.append((rel, w))

    if not changed:
        print("Nothing to change. Everything already uses package imports.")
    else:
        print(f"\n{len(changed)} file(s) {'changed' if APPLY else 'would change'}.")

    for rel, w in warned:
        print(f"WARNING  {rel}: {w}")

    if APPLY and changed:
        print("\nChecking the changed files for syntax errors...")
        bad = 0
        for p in changed:
            try:
                py_compile.compile(str(p), doraise=True)
            except py_compile.PyCompileError as e:
                bad += 1
                print(f"  SYNTAX PROBLEM in {p.name}: {e}")
        print("  all files compile OK" if not bad else f"  {bad} file(s) have problems — restore from the .bak copy")

        left = []
        for p in changed:
            if BARE_FROM.search(p.read_text(encoding="utf-8")):
                left.append(p.name)
        if left:
            print(f"  Still has bare imports: {left}")

        print("\nNext:")
        print("  1) From the backend folder, with your env vars set:   python -c \"import ai_services\"")
        print("  2) Run modules from the ai-services folder:           python -m ai_services.meal_analyzer")
        print("  3) Delete the .bak files when you're happy (and add *.bak to .gitignore).")


if __name__ == "__main__":
    main()