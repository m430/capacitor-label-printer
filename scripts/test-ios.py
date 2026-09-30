#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "ios/Tests"
PLUGIN = ROOT / "ios/Plugin"


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="label-printer-ios-") as directory:
    build = Path(directory)
    for module in ("CoreBluetooth", "Capacitor", "UIKit"):
        run(["swiftc", "-emit-library", "-emit-module", "-module-name", module,
             str(TESTS / f"{module}.swift"), "-emit-module-path", str(build / f"{module}.swiftmodule"),
             "-o", str(build / f"lib{module}.dylib")])

    flags = ["swiftc", "-I", str(build), "-L", str(build), "-lCoreBluetooth", "-lCapacitor", "-lUIKit"]
    sources = [PLUGIN / "IOSPrinterManager.swift", PLUGIN / "IOSStatusMapper.swift", PLUGIN / "LabelPrinterPlugin.swift"]
    environment = {**os.environ, "DYLD_LIBRARY_PATH": str(build)}
    binary = build / "PrinterTests"
    run(flags + [str(p) for p in sources] + [str(TESTS / "PrinterTests.swift"), "-o", str(binary)])
    run([str(binary)], env=environment)
    run(["swiftc", str(PLUGIN / "IOSStatusMapper.swift"), str(TESTS / "StatusMapperTests.swift"),
         "-o", str(build / "StatusMapperTests")])
    run([str(build / "StatusMapperTests")])

    if "--mutations" in sys.argv:
        mutations = [
            ("bridge", "LabelPrinterPlugin.swift", "CAPPlugin, CAPBridgedPlugin", "CAPPlugin"),
            ("raw-bytes", "IOSPrinterManager.swift", "text = payload\n", 'text = payload.replacingOccurrences(of: "\\r\\n", with: "\\n")\n'),
            ("raw-bytes", "IOSPrinterManager.swift", "type: .withResponse)\n", "type: .withResponse)\n        finishWrite(nil)\n"),
            ("status-timeout", "IOSPrinterManager.swift", "if invalidate { queryAllowed = false }", "if invalidate { queryAllowed = true }"),
            ("connect-timeout", "IOSPrinterManager.swift", "central?.cancelPeripheralConnection(peripheral)", "_ = peripheral"),
            ("unnamed-hidden", "IOSPrinterManager.swift", "guard !name.isEmpty else { return }\n        ", ""),
            ("drain-before-complete", "IOSPrinterManager.swift",
             "if job.offset == job.data.count, peripheral.canSendWriteWithoutResponse {",
             "if job.offset == job.data.count {"),
        ]
        for case, filename, old, new in mutations:
            source = (PLUGIN / filename).read_text()
            assert old in source, f"Mutation anchor missing: {case}"
            mutated = build / filename
            mutated.write_text(source.replace(old, new, 1))
            inputs = [mutated if p.name == filename else p for p in sources]
            run(flags + [str(p) for p in inputs] + [str(TESTS / "PrinterTests.swift"), "-o", str(binary)])
            result = subprocess.run([str(binary), case], env=environment, capture_output=True, text=True)
            if result.returncode == 0 or "FAIL:" not in result.stderr:
                raise SystemExit(f"Regression test failed to detect mutation: {case}\n{result.stdout}\n{result.stderr}")
            print(f"PASS: regression detected ({case}): {result.stderr.strip()}")
