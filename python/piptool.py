# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""The piptool module imports pip requirements into Bazel rules."""

import argparse
import json
import os
import sys
import zipfile

# TODO(mattmoor): When this tool is invoked bundled as a PAR file,
# but not as a py_binary, we get a warning that indicates the system
# installed version of PIP is being picked up instead of our bundled
# version, which should be 9.0.1, e.g.
#   You are using pip version 1.5.4, however version 9.0.1 is available.
#   You should consider upgrading via the 'pip install --upgrade pip' command.
try:
  from pip import main as pip_main
except:
  import subprocess

  def pip_main(argv):
    p = subprocess.call(['pip'] + argv)
    return p.returncode

# TODO(mattmoor): We can't easily depend on other libraries when
# being invoked as a raw .py file.  Once bundled, we should be able
# to remove this fallback on a stub implementation of Wheel.
try:
  from python.whl import Wheel
except:
  class Wheel(object):

    def __init__(self, path):
      self._path = path

    def basename(self):
      return os.path.basename(self._path)

    def distribution(self):
      # See https://www.python.org/dev/peps/pep-0427/#file-name-convention
      parts = self.basename().split('-')
      return parts[0]


parser = argparse.ArgumentParser(
    description='Import Python dependencies into Bazel.')

parser.add_argument('--name', action='store',
                    help=('The namespace of the import.'))

parser.add_argument('--input', action='store',
                    help=('The requirements.txt file to import.'))

parser.add_argument('--output', action='store',
                    help=('The requirements.bzl file to export.'))

parser.add_argument('--directory', action='store',
                    help=('The directory into which to put .whl files.'))


def main():
  args = parser.parse_args()

  # https://github.com/pypa/pip/blob/9.0.1/pip/__init__.py#L209
  if pip_main(["wheel", "-w", args.directory, "-r", args.input]):
    sys.exit(1)

  # Enumerate the .whl files we downloaded.
  def list_whls():
    dir = args.directory + '/'
    for root, unused_dirnames, filenames in os.walk(dir):
      for fname in filenames:
        if fname.endswith('.whl'):
          yield os.path.join(root, fname)

  def repo_name(wheel):
    return '{repo}_{pkg}'.format(
      repo=args.name, pkg=wheel.distribution())

  def whl_library(wheel):
    # Indentation here matters.  whl_library must be within the scope
    # of the function below.
    return """
  whl_library(
      name = "{repo_name}",
      whl = "@{name}//:{path}",
      requirements = "@{name}//:requirements.bzl",
  )""".format(name=args.name, repo_name=repo_name(wheel),
              path=wheel.basename())

  whls = [Wheel(path) for path in list_whls()]

  with open(args.output, 'w') as f:
    f.write("""\
# Install pip requirements.
#
# Generated from {input}

load("@io_bazel_rules_python//python:whl.bzl", "whl_library")

def pip_install():
  {whl_libraries}

_packages = {{
  {mappings}
}}

all_packages = _packages.values()

def packages(name):
  name = name.replace("-", "_")
  return _packages[name]
""".format(input=args.input,
           whl_libraries='\n'.join(map(whl_library, whls)),
           mappings=','.join([
             '"%s": "@%s//:pkg"' % (wheel.distribution(), repo_name(wheel))
             for wheel in whls
           ])))

if __name__ == '__main__':
  main()
