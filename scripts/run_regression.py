#!/usr/bin/env python3
"""Run the existing XCTest plan and verify that required workflow tests really ran."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/qa/operation-regressions.json"


def load_manifest():
    manifest = json.loads(MANIFEST.read_text())
    sources = "\n".join(path.read_text() for path in (ROOT / "BingoADHDTests").glob("*.swift"))
    suites = set(re.findall(r"\b(?:class|struct)\s+(\w+Tests)\b", sources))
    integration = (ROOT / manifest["integration_file"]).read_text()
    methods = set(re.findall(r"\bfunc\s+(test\w+)\s*\(", integration))
    mapped = set()
    identifiers = set()
    for operation in manifest["operations"]:
        identity = operation["id"]
        if identity in identifiers:
            raise ValueError(f"Duplicate operation ID: {identity}")
        identifiers.add(identity)
        for suite in operation["existing_suites"]:
            if suite not in suites:
                raise ValueError(f"{identity}: suite does not exist: {suite}")
        for method in operation["integration_tests"]:
            if method not in methods:
                raise ValueError(f"{identity}: integration test does not exist: {method}")
            mapped.add(method)
    if mapped != methods or not mapped:
        raise ValueError(f"Unmapped integration tests: {sorted(methods - mapped)}")
    project = (ROOT / "BingoADHD.xcodeproj/project.pbxproj").read_text()
    phase = re.search(r"B0A1D2E3F4A5061728394D07 /\* Sources \*/ = \{.*?files = \((.*?)\);", project, re.S)
    if phase is None:
        raise ValueError("Could not find the existing unit test source build phase")
    for filename in [Path(manifest["integration_file"]).name, "OperationPersistenceRepository.swift"]:
        if f"/* {filename} in Sources */" not in phase.group(1):
            raise ValueError(f"Missing test build membership: {filename}")
    plan = json.loads((ROOT / "BingoADHDTests/BingoADHDTests.xctestplan").read_text())
    targets = [entry for entry in plan["testTargets"] if entry["target"]["name"] == manifest["target"]]
    if len(targets) != 1 or targets[0].get("skipped", False) or targets[0].get("skippedTests"):
        raise ValueError("The existing regression target is missing, disabled, or has skipped tests")
    if targets[0].get("selectedTests"):
        raise ValueError("The full test plan must not silently select only a subset")
    ui_methods = required_ui_tests(manifest)
    ui_targets = [entry for entry in plan["testTargets"] if entry["target"]["name"] == manifest["ui_target"]]
    if len(ui_targets) != 1 or any(ui_targets[0].get(key) for key in ["skipped", "skippedTests", "selectedTests"]):
        raise ValueError("UI target must be enabled without test filtering in the existing plan")
    if not ui_methods or Path(manifest["ui_file"]).name + " in Sources */" not in project:
        raise ValueError("UI workflows are not included in the Xcode project")
    return manifest, mapped


def required_ui_tests(manifest):
    source = (ROOT / manifest["ui_file"]).read_text()
    methods = set(re.findall(r"\bfunc\s+(test\w+)\s*\(", source))
    mapped = {method for operation in manifest["operations"] for method in operation["ui_tests"]}
    if mapped != methods:
        raise ValueError(f"UI mapping differs from executable tests: {sorted(mapped ^ methods)}")
    return methods


def create_isolated_simulator(destination):
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
    versions = {item["identifier"]: tuple(map(int, item["version"].split("."))) for item in runtimes}
    candidates = [(runtime, device) for runtime, entries in devices.items() for device in entries
                  if device.get("deviceTypeIdentifier", "").startswith("com.apple.CoreSimulator.SimDeviceType.iPhone")]
    if destination != "auto":
        requested = dict(item.split("=", 1) for item in destination.split(",") if "=" in item)
        candidates = [(runtime, device) for runtime, device in candidates
                      if (requested.get("id") == device["udid"] or requested.get("name") == device["name"])
                      and ("OS" not in requested or requested["OS"] == runtime.split(".iOS-")[-1].replace("-", "."))]
    else:
        candidates = [item for item in candidates if "Duo" not in item[1]["deviceTypeIdentifier"]]
        # Fresh CI images may have a runtime but no pre-created devices.
        if not candidates:
            for runtime in runtimes:
                if not runtime.get("isAvailable") or ".iOS-" not in runtime["identifier"]:
                    continue
                phones = [phone for phone in runtime.get("supportedDeviceTypes", [])
                          if phone.get("productFamily") == "iPhone" and "Duo" not in phone["name"]]
                if phones:
                    phone = phones[0]
                    candidates.append((runtime["identifier"], {"deviceTypeIdentifier": phone["identifier"]}))
        candidates.sort(key=lambda item: versions[item[0]], reverse=True)
    if not candidates:
        raise ValueError("No available iPhone simulator matches the destination")
    runtime, template = candidates[0]
    name = "Bingodays Regression " + str(uuid.uuid4())[:8]
    device_id = subprocess.check_output(
        ["xcrun", "simctl", "create", name, template["deviceTypeIdentifier"], runtime], text=True).strip()
    return device_id, runtime


def result_failures(summary, passed_methods, required_methods, passed_ui=None, required_ui=None):
    failures = []
    if summary.get("result") != "Passed":
        failures.append("Xcode did not report Passed")
    if summary.get("totalTestCount", 0) <= 0 or summary.get("passedTests", 0) <= 0:
        failures.append("No passing tests were executed")
    for field in ["failedTests", "skippedTests", "expectedFailures"]:
        if field not in summary or summary[field] != 0:
            failures.append(f"{field} must be present and zero")
    missing = sorted(required_methods - passed_methods)
    if missing:
        failures.append("Required integration tests did not pass: " + ", ".join(missing))
    missing_ui = sorted((required_ui or set()) - (passed_ui or set()))
    if missing_ui:
        failures.append("Required UI tests did not pass: " + ", ".join(missing_ui))
    return failures


def main():
    def interrupt_run(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupt_run)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", help="auto or platform=iOS Simulator,id=...; uses a fresh device of that type/runtime")
    parser.add_argument("--mode", choices=["full", "integration", "ui"], default="full")
    parser.add_argument("--verify-only", action="store_true", help="Check operation/test mappings without building")
    parser.add_argument("--report", type=Path, default=ROOT / ".codex-artifacts-regression/latest-report.json")
    parser.add_argument("--keep-results", action="store_true", help="Keep this run's log and xcresult for investigation")
    args = parser.parse_args()
    manifest, required = load_manifest()
    ui_required = required_ui_tests(manifest)
    print(f"Catalog mappings valid: {len(manifest['operations'])} operations; "
          f"{len(required)} integration + {len(ui_required)} UI tests.", flush=True)
    if args.verify_only:
        return 0
    if not args.destination or (args.destination != "auto" and not args.destination.startswith("platform=iOS Simulator,")):
        parser.error("Use an explicit iOS Simulator destination; this runner must not modify a personal device")
    checks = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "scripts/tests"], cwd=ROOT)
    if checks.returncode:
        return checks.returncode

    # Only coordinates invocations of this runner. Xcode/manual xcodebuild users
    # must still avoid concurrent builds against the checkout's default DerivedData.
    digest = hashlib.sha256(str(ROOT).encode()).hexdigest()[:16]
    lock_path = Path(tempfile.gettempdir()) / f"bingodays-regression-{digest}.lock"
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another regression run for this checkout is already active")
        work = Path(tempfile.mkdtemp(prefix="bingodays-regression-"))
        log_path = work / "xcodebuild.log"
        result_path = work / "Tests.xcresult"
        command = ["xcodebuild", "test", "-project", "BingoADHD.xcodeproj", "-scheme", "BingoADHD",
                   "-destination", args.destination, "-parallel-testing-enabled", "NO",
                   "-resultBundlePath", str(result_path), "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
        if args.mode == "integration":
            command.append(f"-only-testing:{manifest['target']}/{manifest['integration_suite']}")
        elif args.mode == "ui":
            command.append(f"-only-testing:{manifest['ui_target']}/{manifest['ui_suite']}")
        required = required if args.mode != "ui" else set()
        ui_required = ui_required if args.mode != "integration" else set()
        report = {"started_at": datetime.now(timezone.utc).isoformat(), "mode": args.mode,
                  "destination": args.destination, "command": command, "status": "failed",
                  "required_integration_tests": sorted(required), "required_ui_tests": sorted(ui_required), "failures": []}
        isolated_id = None
        try:
            isolated_id, runtime = create_isolated_simulator(args.destination)
            actual_destination = f"platform=iOS Simulator,id={isolated_id}"
            command[command.index("-destination") + 1] = actual_destination
            report["isolated_simulator"] = {"id": isolated_id, "runtime": runtime}
            print(f"Running {args.mode} regression; log: {log_path}", flush=True)
            with log_path.open("w") as log:
                with subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                      start_new_session=True) as build:
                    try:
                        build.wait()
                    except KeyboardInterrupt:
                        os.killpg(build.pid, signal.SIGTERM)
                        try:
                            build.wait(timeout=15)
                        except subprocess.TimeoutExpired:
                            os.killpg(build.pid, signal.SIGKILL)
                            build.wait()
                        raise
            log_text = log_path.read_text(errors="replace")
            suite = re.escape(manifest["integration_suite"])
            passed = set(re.findall(rf"Test Case '-\[\S*{suite} (test\w+)\]' passed", log_text))
            report["passed_integration_tests"] = sorted(passed)
            ui_suite = re.escape(manifest["ui_suite"])
            ui_passed = set(re.findall(rf"Test Case '-\[\S*{ui_suite} (test\w+)\]' passed", log_text))
            report["passed_ui_tests"] = sorted(ui_passed)
            if build.returncode:
                report["failures"].append(f"xcodebuild exited with {build.returncode}")
            summary_process = subprocess.run(
                ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path), "--compact"],
                capture_output=True, text=True)
            if summary_process.returncode:
                report["failures"].append("No readable xcresult summary; a build alone cannot pass this gate")
            else:
                summary = json.loads(summary_process.stdout)
                report["summary"] = summary
                report["failures"].extend(result_failures(summary, passed, required, ui_passed, ui_required))
            if not report["failures"]:
                report["status"] = "passed"
            else:
                print("\n".join(log_text.splitlines()[-25:]), file=sys.stderr)
        except KeyboardInterrupt:
            report["failures"].append("Regression interrupted")
        except Exception as error:
            report["failures"].append(str(error))
        finally:
            if isolated_id:
                subprocess.run(["xcrun", "simctl", "shutdown", isolated_id], capture_output=True)
                deletion = subprocess.run(["xcrun", "simctl", "delete", isolated_id], capture_output=True, text=True)
                if deletion.returncode:
                    report["failures"].append(f"Could not clean isolated simulator {isolated_id}: {deletion.stderr}")
                    report["status"] = "failed"
            report["finished_at"] = datetime.now(timezone.utc).isoformat()
            if args.keep_results:
                report["retained_results"] = str(work)
            else:
                try:
                    # This exact directory was created by this invocation only.
                    shutil.rmtree(work)
                except OSError as error:
                    report["failures"].append(f"Cleanup failed for {work}: {error}")
                    report["status"] = "failed"
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"Regression {report['status']}; report: {args.report}")
        for failure in report["failures"]:
            print(f"- {failure}", file=sys.stderr)
        return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
