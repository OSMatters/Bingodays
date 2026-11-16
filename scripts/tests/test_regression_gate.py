import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import json


spec = importlib.util.spec_from_file_location("regression_runner", Path(__file__).parents[1] / "run_regression.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RegressionGateTests(unittest.TestCase):
    def setUp(self):
        self.summary = {"result": "Passed", "totalTestCount": 2, "passedTests": 2,
                        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.required = {"testSave", "testReload"}

    def testCompletePassingRunIsAccepted(self):
        self.assertEqual(runner.result_failures(self.summary, self.required, self.required), [])

    def testSuccessfulBuildWithNoExecutedTestsIsRejected(self):
        self.summary.update(totalTestCount=0, passedTests=0)
        self.assertTrue(runner.result_failures(self.summary, set(), self.required))

    def testMissingWorkflowCannotBeHiddenByOtherPassingTests(self):
        self.summary.update(totalTestCount=900, passedTests=900)
        self.assertTrue(runner.result_failures(self.summary, {"testSave"}, self.required))

    def testSkippedOrExpectedFailureCannotPassTheGate(self):
        for field in ["failedTests", "skippedTests", "expectedFailures"]:
            with self.subTest(field=field):
                summary = dict(self.summary, **{field: 1})
                self.assertTrue(runner.result_failures(summary, self.required, self.required))

    def testIncompleteSummaryIsRejected(self):
        del self.summary["skippedTests"]
        self.assertTrue(runner.result_failures(self.summary, self.required, self.required))

    def testUnitOnlySuccessCannotPassFullUIGate(self):
        self.summary.update(totalTestCount=823, passedTests=823)
        self.assertTrue(runner.result_failures(self.summary, self.required, self.required,
                                             set(), {"testTaskDeleteDoesNotReopen"}))

    def testFullRunRequiresBothIntegrationAndUIResults(self):
        ui = {"testCreateTaskSaveSurvivesRelaunch"}
        self.assertEqual(runner.result_failures(self.summary, self.required, self.required, ui, ui), [])

    def testStaleOrMissingUIMappingIsRejected(self):
        manifest, _ = runner.load_manifest()
        mapped = [operation for operation in manifest["operations"] if operation["ui_tests"]]
        self.assertTrue(mapped)
        mapped[0]["ui_tests"].append("testNoLongerExists")
        with self.assertRaises(ValueError):
            runner.required_ui_tests(manifest)
        mapped[0]["ui_tests"].pop()
        mapped[0]["ui_tests"].pop()
        with self.assertRaises(ValueError):
            runner.required_ui_tests(manifest)

    def testFreshCIImageCanCreateDeviceFromRuntimeWithoutExistingDevices(self):
        runtimes = {"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                    "version": "27.2", "isAvailable": True, "supportedDeviceTypes": [
                        {"identifier": "iPhone-17", "name": "iPhone 17", "productFamily": "iPhone"}]}]}
        with patch.object(runner.subprocess, "check_output", side_effect=[
                json.dumps({"devices": {}}), json.dumps(runtimes), "owned-simulator\n"]) as call:
            identity, runtime = runner.create_isolated_simulator("auto")
        self.assertEqual(identity, "owned-simulator")
        self.assertTrue(runtime.endswith("iOS-27-2"))
        command = call.call_args.args[0]
        self.assertEqual(command[:3], ["xcrun", "simctl", "create"])
        self.assertTrue(command[3].startswith("Bingodays Regression "))
        self.assertEqual(command[4], "iPhone-17")

    def testCatalogReferencesCurrentExistingTests(self):
        manifest, required = runner.load_manifest()
        self.assertEqual(manifest["target"], "BingoADHDTests")
        self.assertGreater(len(required), 0)


if __name__ == "__main__":
    unittest.main()
