load("@bazel_tools//tools/build_defs/repo:cache.bzl", "get_default_canonical_id")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

cc_library_headers = """load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "headers",
    hdrs = glob(["**"]),
    includes = ["."],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "header_files",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)
"""

cc_library_sources = """filegroup(
     name = "sources",
     srcs = glob(["**"]),
     visibility = ["//visibility:public"],
 )
 """

shared_build_content = """load("@rules_cc//cc:defs.bzl", "cc_library", "cc_shared_library")
load("@bzlmodrio-opencv//private/cpp/opencv:wrapped_cc_import.bzl", "wrapped_cc_import")
load("@bzlmodrio-opencv//private/cpp/opencv:wrapped_cc_import.bzl", "cc_import_name")

JNI_PATTERN=[
    "**/*jni.dll",
    "**/*jni.so*",
    "**/*jni.dylib",
    "**/*_java*.dll",
    "**/lib*_java*.dylib",
    "**/lib*_java*.so",
]

shared_srcs = glob([
        "**/*.dll",
        "**/*.so*",
        "**/*.dylib",
    ],
    exclude=JNI_PATTERN + ["**/*.so*.debug"],
    allow_empty = True,
)

shared_jni_srcs = glob(JNI_PATTERN, exclude=["**/*.so*.debug"], allow_empty=True)

[ wrapped_cc_import(
    x,
    "%static_name",
    hdrs = ["@org_wpilib_opencv-cpp_headers//:header_files"],
    includes = ["."]
) for x in shared_srcs ]

# Create the static aggregator library.
cc_library(
    name = "static",
    deps = [":" + cc_import_name(x) for x in shared_srcs] + [
        "@org_wpilib_opencv-cpp_headers//:headers",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "jni",
    srcs = shared_jni_srcs + shared_srcs,
    visibility = ["@bzlmodrio-opencv//:__subpackages__"],
)
"""

static_build_content = """load("@bzlmodrio-opencv//private/cpp/opencv:wrapped_cc_import.bzl", "static_alias")

exports_files(glob(["**"]))

libraries = glob(["**/*.lib", "**/*.a"], allow_empty=True)

static_alias(
    name = "static_library_file",
    libraries = libraries,
    visibility = ["//visibility:public"],
)
"""

def _update_integrity_attr(ctx, attrs, download_info):
    if ctx.attr.sha256:
        return ctx.repo_metadata(reproducible = True)

    fail("sha256 required for", ctx.label)

_download_and_generate_attrs = {
    "integrity": attr.string(),
    "sha256": attr.string(),
    "static_repository_name": attr.string(),
    "url": attr.string(),
}

def _download_and_generate_impl(rctx):
    urls = [rctx.attr.url]

    rctx.download_and_extract(
        url = urls,
        sha256 = rctx.attr.sha256,
        canonical_id = get_default_canonical_id(rctx, urls),
    )

    rctx.file("WORKSPACE", "")

    rctx.file("BUILD.bazel", shared_build_content.replace("%static_name", rctx.attr.static_repository_name))
    rctx.file("libs.bzl", """load("@bzlmodrio-opencv//private/cpp/opencv:wrapped_cc_import.bzl", "cc_import_name")
shared_srcs = glob([
        "**/*.dll",
        "**/*.so*",
        "**/*.dylib",
    ],
    allow_empty = True,
)

# The list of shared libraries to link against for opencv.
# This needs to be a list rather than a target so we don't try to dynamically link the list target.
# CcSharedLibraryInfo only supports 1 link target per dependency.
shared_libraries = [ cc_import_name(x) for x in shared_srcs ]
""")

    if rctx.attr.sha256:
        return rctx.repo_metadata(reproducible = True)

    fail("sha256 required for", rctx.label)

_download_and_generate = repository_rule(
    implementation = _download_and_generate_impl,
    attrs = _download_and_generate_attrs,
)

def _get_maven_version(mctx):
    for mod in mctx.modules:
        if mod.name == "bzlmodrio-opencv":
            for tag in mod.tags.version:
                return tag.maven_version
    fail("bzlmodrio-opencv must call deps.version(maven_version = ...)")

def __setup_bzlmodrio_opencv_cpp_dependencies(mctx):
    maven_version = _get_maven_version(mctx)
    base_url = "https://frcmaven.wpi.edu/release/org/wpilib/thirdparty/opencv/opencv-cpp/" + maven_version + "/opencv-cpp-" + maven_version + "-"

    headers_hash = "e1454fadad5c6b525a43388e7be63bc6d5e25f74c221ab5ad18f2b3f61f030d6"
    sources_hash = "d54070cb21a52f034aab0e07f37ae720d3f6a6279925274f9980ce1af15a7295"

    hash_pairs = {
        "linuxarm64": ("dedd410d37d81ed45a32f89c4b421f19adc7152b0b27e2bba53dd8b880171ffc", "a1666b92ae9d434bb5cf2c43ee1c39d7cae64d661a0ad0516d7d9ef719936a0a"),
        "linuxarm64debug": ("da6d822474f7a9aca2ac5606075e9c38b3caea52ea77c47484955239c278c4b9", "15761705913b82b7547866d48c5b22062c58dbb1f52df787828144ac100f86e2"),
        "linuxsystemcore": ("90c1ecbc7b1192435c558a462b9d2448931e118e937bc05437fa0b9137d8366d", "ced7f8513ba12d8a23d32b5c102de4771f7eba468a1043bc92e415e8494c84c7"),
        "linuxsystemcoredebug": ("afd42ef9e8a3421045ed14f65d73a279dffe77b9f91c46e6829ff48cfb443a83", "33086e571522669c4ae89adf3c5eafe9a0ce008728e3711ca7ce8dcfa5fb772a"),
        "linuxx86-64": ("df562dea20e832ed3191003e28077e9ff9ff3f9cdd147e8acce475b28ef3f2ac", "47ad7b5f6d5fd56a8bdd791969fd666bda73ea651a57edd6de9e00a3404accb5"),
        "linuxx86-64debug": ("3cef6e58e65131aaccc85cefa3400169172d24eda10a228fb782763f5fc37843", "ee5c94037bfb872e67b113f9c71078f97a6dbf1025a0b8ec90de1bb8d0668e9a"),
        "osxarm64": ("b4395bc7055bfd9bf6629db773114c41d74c5d3f1221567b394a3a82471ba8f0", "c71e49f4119f4c657985bb84a0f4a68c7cae293e8ad681a7a061ec9a189d8ce4"),
        "osxarm64debug": ("8e92ff11763dbb21739b05a5cd280c5e49988453bc38c1721634d0c459f01a36", "9724cef14f7e54db0379d294e4a355539a65d5a4aeab081ccd43927d82b44d3b"),
        "osxuniversal": ("e95704806bf828b2fbbb735d7b51cfbdf02a6065cbbe190c36ca16fe1fc49f2f", "80eabd49e90c04b8e9959b1855034da8996ee465e1caa585b8f3b798a1df3fda"),
        "osxuniversaldebug": ("1782dae9494ddbeed275f167654ac22abd942e9947af4031a8b4f31400eec5e1", "8aef12004e1f0e79607d3bb9bc62972baa0ef8b0a0044172f91d4dcc565b2c04"),
        "osxx86-64": ("b1a5d3ebab801c94709c9fe5e0e5959f6b0a0c67beb07120be1840785ca2bddf", "0751d031bc300450f5db8f106cdc94636993f7376e9c8fb06face2521fe7d59f"),
        "osxx86-64debug": ("493ce50da6ea839322564a0f54029714aef3879f6b8dd3fb280565b126b8535c", "30929a678faa086e7287009c64a6900eb1c813c4fbedc3790c978481168bb66f"),
        "windowsarm64": ("c493364ace960a1fe276765d6c3c68381ad0d7646a05ece78877ae4bb6b0a21e", "8fcf6b939cfe010d8b9ac30d530a4f689669ab1d964825aca1f6e27e4bc5e45b"),
        "windowsarm64debug": ("dd0d4e21b3219c08cfa89947c7d0099022ab4ffec4a8d40302ca0ca6d1be0f31", "0347445f2229007451b4eac70dea124ddb43f56c484248a07091db38ad12830f"),
        "windowsx86-64": ("a62ae58896626fb6c8bfb863c1af67b23bb4b1844620d99d65a1d8f4b095b953", "cdc2319d047ab3238ac84d1dbbd75751689e09e4966ebdd4a3e91101326c2bd6"),
        "windowsx86-64debug": ("a36baa0ea955179cc55a25ab22125b52b7602b47d60115ec5e3ba89e6e94567a", "4aac1f8c233968c28214882b545262eaf4490d8d0983f059ffe3b8a60eceae33"),
    }

    maybe(
        http_archive,
        "org_wpilib_opencv-cpp_headers",
        url = base_url + "headers.zip",
        sha256 = headers_hash,
        build_file_content = cc_library_headers,
    )
    maybe(
        http_archive,
        "org_wpilib_opencv-cpp_sources",
        url = base_url + "sources.zip",
        sha256 = sources_hash,
        build_file_content = cc_library_sources,
    )

    for platform, (shared_sha256, static_sha256) in hash_pairs.items():
        shared_name = platform
        if platform.endswith("debug"):
            static_name = platform[:-5] + "staticdebug"
        else:
            static_name = platform + "static"

        shared_url = base_url + shared_name + ".zip"
        static_url = base_url + static_name + ".zip"
        static_repository_name = "org_wpilib_opencv-cpp_" + static_name
        shared_repository_name = "org_wpilib_opencv-cpp_" + shared_name
        maybe(
            http_archive,
            static_repository_name,
            url = static_url,
            sha256 = static_sha256,
            build_file_content = static_build_content,
        )
        maybe(
            _download_and_generate,
            shared_repository_name,
            url = shared_url,
            sha256 = shared_sha256,
            static_repository_name = static_repository_name,
        )

    return mctx.extension_metadata(
        reproducible = True,
    )

_version_tag = tag_class(
    attrs = {
        "maven_version": attr.string(mandatory = True),
    },
)

deps = module_extension(
    __setup_bzlmodrio_opencv_cpp_dependencies,
    tag_classes = {
        "version": _version_tag,
    },
)
