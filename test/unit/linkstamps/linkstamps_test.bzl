"""Unittests for rust linkstamp support."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:defs.bzl", "cc_library")
load("//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//test/unit:common.bzl", "assert_action_mnemonic")

def _is_running_on_linux(ctx):
    return ctx.target_platform_has_constraint(ctx.attr._linux[platform_common.ConstraintValueInfo])

def _supports_linkstamps_test(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    if not _is_running_on_linux(ctx):
        # Skipping linkstamps tests on an unsupported (non-Linux) platform
        return analysistest.end(env)

    linkstamp_action = tut.actions[0]
    assert_action_mnemonic(env, linkstamp_action, "CppLinkstampCompile")
    linkstamp_out = linkstamp_action.outputs.to_list()[0]
    asserts.equals(env, linkstamp_out.basename, "linkstamp.o")
    tut_out = tut.files.to_list()[0]
    workspace_prefix = "" if ctx.workspace_name == "rules_rust" else "/external/rules_rust"

    expected_linkstamp_path = tut_out.dirname + "/_objs/" + tut_out.basename + workspace_prefix + "/test/unit/linkstamps/linkstamp.o"
    asserts.equals(
        env,
        linkstamp_out.path,
        expected_linkstamp_path,
        "Expected linkstamp output '{actual_path}' to match '{expected_path}'".format(
            actual_path = linkstamp_out.path,
            expected_path = expected_linkstamp_path,
        ),
    )

    rustc_action = tut.actions[1]
    assert_action_mnemonic(env, rustc_action, "Rustc")
    rustc_inputs = rustc_action.inputs.to_list()
    asserts.true(
        env,
        linkstamp_out in rustc_inputs,
        "Expected linkstamp output '{output}' to be among the binary inputs '{inputs}'".format(
            output = linkstamp_out,
            inputs = rustc_inputs,
        ),
    )
    return analysistest.end(env)

supports_linkstamps_test = analysistest.make(
    _supports_linkstamps_test,
    attrs = {
        "_linux": attr.label(default = Label("@platforms//os:linux")),
    },
)

def _linkstamps_test():
    # Native linkstamps are only supported by the builtin Linux C++ toolchain. Ideally,
    # we would be able to inspect the feature_configuration of the target to see if
    # it has the "linkstamp" feature, but there is no way to get that feature
    # configuration.
    cc_library(
        name = "cc_lib_with_linkstamp",
        linkstamp = select({
            "//rust/platform:linux": "linkstamp.cc",
            "//conditions:default": None,
        }),
    )

    rust_binary(
        name = "some_rust_binary",
        srcs = ["foo.rs"],
        edition = "2018",
        deps = [":cc_lib_with_linkstamp"],
    )

    supports_linkstamps_test(
        name = "rust_binary_supports_linkstamps_test",
        target_under_test = ":some_rust_binary",
    )

    rust_library(
        name = "some_rust_library_with_linkstamp_transitively",
        srcs = ["foo.rs"],
        edition = "2018",
        deps = [":cc_lib_with_linkstamp"],
    )

    rust_binary(
        name = "some_rust_binary_with_linkstamp_transitively",
        srcs = ["foo.rs"],
        edition = "2018",
        deps = [":some_rust_library_with_linkstamp_transitively"],
    )

    supports_linkstamps_test(
        name = "rust_binary_with_linkstamp_transitively",
        target_under_test = ":some_rust_binary_with_linkstamp_transitively",
    )

    cc_library(
        name = "cc_lib_with_linkstamp_transitively",
        deps = [":cc_lib_with_linkstamp"],
    )

    rust_binary(
        name = "some_rust_binary_with_multiple_paths_to_a_linkstamp",
        srcs = ["foo.rs"],
        edition = "2018",
        deps = [":cc_lib_with_linkstamp", ":cc_lib_with_linkstamp_transitively"],
    )

    supports_linkstamps_test(
        name = "rust_binary_supports_duplicated_linkstamps",
        target_under_test = ":some_rust_binary_with_multiple_paths_to_a_linkstamp",
    )

    rust_test(
        name = "some_rust_test1",
        srcs = ["foo.rs"],
        edition = "2018",
        deps = [":cc_lib_with_linkstamp"],
    )

    supports_linkstamps_test(
        name = "rust_test_supports_linkstamps_test1",
        target_under_test = ":some_rust_test1",
    )

    rust_test(
        name = "some_rust_test2",
        srcs = ["foo.rs"],
        edition = "2018",
        deps = [":cc_lib_with_linkstamp"],
    )

    supports_linkstamps_test(
        name = "rust_test_supports_linkstamps_test2",
        target_under_test = ":some_rust_test2",
    )

def linkstamps_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
      name: Name of the macro.
    """

    # Older versions of Bazel do not support Starlark linkstamps.
    if not hasattr(cc_common, "register_linkstamp_compile_action"):
        # buildifier: disable=print
        print("Skipping linkstamps tests since this Bazel version does not support Starlark linkstamps.")
        return

    _linkstamps_test()

    native.test_suite(
        name = name,
        tests = [
            ":rust_binary_supports_linkstamps_test",
            ":rust_binary_supports_duplicated_linkstamps",
            ":rust_test_supports_linkstamps_test1",
            ":rust_test_supports_linkstamps_test2",
        ],
    )
