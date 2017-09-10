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
"""Import pip requirements into Bazel."""

# We pin to a particular version of get-pip.py from its Git repo,
# and use it to install a particular version of pip.
PIP_VERSION = "9.0.1"
GETPIP_COMMIT = "430ba37776ae2ad89f794c7a43b90dc23bac334c"
GETPIP_CHECKSUM = (
  "083a66e0b86379a425abe677f5f58b1d7d1bcf483c47751ea65ff0eacf870b99")

def _import_impl(repository_ctx):
  """Core implementation of pip_import."""

  # Add an empty top-level BUILD file.
  repository_ctx.file("BUILD", "")

  # Make sure we have pip installed first.
  getpip_result = repository_ctx.execute([
    "python", repository_ctx.path(repository_ctx.attr._getpip),
    "pip==" + PIP_VERSION
  ])

  if getpip_result.return_code:
    fail("get-pip failed: %s (%s)" % (getpip_result.stdout,
                                      getpip_result.stderr))

  # To see the output, pass: quiet=False
  result = repository_ctx.execute([
    "python", repository_ctx.path(repository_ctx.attr._script),
    "--name", repository_ctx.attr.name,
    "--input", repository_ctx.path(repository_ctx.attr.requirements),
    "--output", repository_ctx.path("requirements.bzl"),
    "--directory", repository_ctx.path(""),
  ])

  if result.return_code:
    fail("pip_import failed: %s (%s)" % (result.stdout, result.stderr))

pip_import = repository_rule(
    attrs = {
        "requirements": attr.label(
            allow_files = True,
            mandatory = True,
            single_file = True,
        ),
        "_script": attr.label(
            executable = True,
            default = Label("//python:piptool.py"),
            cfg = "host",
        ),
        "_getpip": attr.label(
            executable = True,
            default = Label("@getpip//file:get-pip.py"),
            cfg = "host",
        ),
    },
    implementation = _import_impl,
)
"""A rule for importing <code>requirements.txt</code> dependencies into Bazel.

This rule imports a <code>requirements.txt</code> file and generates a new
<code>requirements.bzl</code> file.  This is used via the <code>WORKSPACE</code>
pattern:
<pre><code>pip_import(
    name = "foo",
    requirements = ":requirements.txt",
)
load("@foo//:requirements.bzl", "pip_install")
pip_install()
</code></pre>

You can then reference imported dependencies from your <code>BUILD</code>
file with:
<pre><code>load("@foo//:requirements.bzl", "packages")
py_library(
    name = "bar",
    ...
    deps = [
       "//my/other:dep",
       packages("futures"),
       packages("mock"),
    ],
)
</code></pre>

Or alternatively:
<pre><code>load("@foo//:requirements.bzl", "all_packages")
py_binary(
    name = "baz",
    ...
    deps = [
       ":foo",
    ] + all_packages,
)
</code></pre>

Args:
  requirements: The label of a requirements.txt file.
"""


def pip_repositories():
  """Pull in dependencies needed for pulling in pip dependencies.

  A placeholder method that will eventually pull in any dependencies
  needed to install pip dependencies.
  """
  # Fetch this individual file instead of git_repository because this repo
  # checks in get-pip.py, which embeds a base85 encoded copy of pip.
  # See: https://github.com/pypa/get-pip
  native.http_file(
      name = "getpip",
      url = ("https://raw.githubusercontent.com/" +
             "pypa/get-pip/" + GETPIP_COMMIT + "/2.6/get-pip.py"),
      sha256 = GETPIP_CHECKSUM,
      executable = False,
  )
