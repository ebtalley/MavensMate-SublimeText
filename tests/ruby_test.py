import mavensmate

import unittest
import subprocess
import os

# Note: This test can only be run from within Sublime Text 2
#       because it needs the Sublime Text 2 Plugin Context 'mavensmate'


class RubyTest(unittest.TestCase):

    def test_all(self):
        cwd = os.getcwd()
        try:
            os.chdir(mavensmate.mm_dir)
            p = subprocess.Popen('rake', stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
            (stdout, stderr) = p.communicate()
            self.assertEqual(0, p.returncode, msg=stdout)
        finally:
            os.chdir(cwd)
