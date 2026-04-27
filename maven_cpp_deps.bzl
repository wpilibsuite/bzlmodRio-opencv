load("@bazel_tools//tools/build_defs/repo:cache.bzl", "get_default_canonical_id")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

cc_library_headers = """cc_library(
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

def __static_shared_pair(mctx, name, shared_sha256, static_sha256):
    shared_name = name
    if name.endswith("debug"):
        static_name = name[:-5] + "staticdebug"
    else:
        static_name = name + "static"

    shared_url = "https://frcmaven.wpi.edu/release/org/wpilib/thirdparty/opencv/opencv-cpp/2027-4.13.0-3/opencv-cpp-2027-4.13.0-3-" + shared_name + ".zip"
    static_url = "https://frcmaven.wpi.edu/release/org/wpilib/thirdparty/opencv/opencv-cpp/2027-4.13.0-3/opencv-cpp-2027-4.13.0-3-" + static_name + ".zip"
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

def __setup_bzlmodrio_opencv_cpp_dependencies(mctx):
    maybe(
        http_archive,
        "org_wpilib_opencv-cpp_headers",
        url = "https://frcmaven.wpi.edu/release/org/wpilib/thirdparty/opencv/opencv-cpp/2027-4.13.0-3/opencv-cpp-2027-4.13.0-3-headers.zip",
        sha256 = "e1454fadad5c6b525a43388e7be63bc6d5e25f74c221ab5ad18f2b3f61f030d6",
        build_file_content = cc_library_headers,
    )
    maybe(
        http_archive,
        "org_wpilib_opencv-cpp_sources",
        url = "https://frcmaven.wpi.edu/release/org/wpilib/thirdparty/opencv/opencv-cpp/2027-4.13.0-3/opencv-cpp-2027-4.13.0-3-sources.zip",
        sha256 = "28b35e66a3cc6c4667cddd915ad4db8182fd45482595d8efdc73e08b006ceeab",
        build_file_content = cc_library_sources,
    )
    __static_shared_pair(
        mctx,
        name = "linuxsystemcore",
        shared_sha256 = "0b8628bc0c0c0e7b45c93dde740203ba45d5157ed98273145f5f148e890acc11",
        static_sha256 = "74aad4a7f48519d097c532e08d67b8429d55fb0699257a86b5641de7b038f35a",
    )
    __static_shared_pair(
        mctx,
        name = "linuxsystemcoredebug",
        shared_sha256 = "de2552db3994d846d018c43e2a5f7619328edb0708a0db10dd7e050e7fc0907a",
        static_sha256 = "c7aa613d8c7e6231abd825a99660d4cfdeea132fd6023856e9b55d0f283dc95e",
    )
    __static_shared_pair(
        mctx,
        name = "linuxarm64",
        shared_sha256 = "90a81046e444fe035cdc4795e74149df8e31a70ba817f4c2e8b2966b71f92b85",
        static_sha256 = "2f4f65049e8418d4132fa0b0e95164a3e14cf5938c14a3525e5760dda34d5984",
    )
    __static_shared_pair(
        mctx,
        name = "linuxx86-64",
        shared_sha256 = "9da8059c46572071bacd13f0b2288282e65853abbee9ba0cce99eeee7d0a8b59",
        static_sha256 = "ab3b4bd1ef182bd4e6f16d7c9569147667e2a89ab8799f4d0de9c463f2399789",
    )
    __static_shared_pair(
        mctx,
        name = "osxarm64",
        shared_sha256 = "5b04598eed6e4f33994aa834d7df13d862a97571cc1aca43f2f402f520878568",
        static_sha256 = "6512c351254d34b33e796c2a9103fe7771a2b0cda582443b98d26ecbc819d04b",
    )
    __static_shared_pair(
        mctx,
        name = "osxuniversal",
        shared_sha256 = "1dadc172e9241d0dfc10f506d76a8635e1726f09f9d329aa2c8853a0d3ef63d4",
        static_sha256 = "d1fc11ff74a06dbb721945564b254b6e25a9e98eb47258adca80d49ee076a9d2",
    )
    __static_shared_pair(
        mctx,
        name = "osxx86-64",
        shared_sha256 = "1be9dcc9db720224ec024215c8b7ad7cffe72323122727a773184ddef4c38579",
        static_sha256 = "912cea1c5b29aeda4befe09cc50882a22b180e3c798e35fda678a18130ac0183",
    )
    __static_shared_pair(
        mctx,
        name = "windowsx86-64",
        shared_sha256 = "47843b292e5b4c5f0331fc6c8f3d26a3f22db2438e25379eb87bbb28a6be1288",
        static_sha256 = "34e9c1b5af0d37622f0b9d40fed408aeecc46d772eb64278cf2318e0892e0e31",
    )
    __static_shared_pair(
        mctx,
        name = "windowsarm64",
        shared_sha256 = "52f8a756cc79f8822d6b47a79a5eeaa4a142df59a11882ae7f212377723641c8",
        static_sha256 = "4c4eacfbee78e497da6178d95f9417d8f3b84a193769b26dd5138f0e43803e76",
    )
    __static_shared_pair(
        mctx,
        name = "linuxarm64debug",
        shared_sha256 = "364a7f50320f8dbd69a6fb1ee89caf3570393a9c86c38ebc22c649256f700e23",
        static_sha256 = "7884e90b4e51f75216a1b875e1039ca96d2b5aab47d88a64ea4d1a812fe625a7",
    )
    __static_shared_pair(
        mctx,
        name = "linuxx86-64debug",
        shared_sha256 = "20c2882dc8bfaef50f4eb10f28ccc9d385cbe58750a917ce2571a2e787f5411d",
        static_sha256 = "994c2a30ab9aecdfee2730f198d2aa9cc920be4480c2f4a13cd569714b8274c9",
    )
    __static_shared_pair(
        mctx,
        name = "osxarm64debug",
        shared_sha256 = "3d9f17248cd9f65bd37839b4fc838e167776139770fbe7ecec7936fb94a77741",
        static_sha256 = "79c61cf30d5559a60f2f37a778bd8b890ace738bee0a94229018f0997a191fd6",
    )
    __static_shared_pair(
        mctx,
        name = "osxuniversaldebug",
        shared_sha256 = "f119c67f6dcfef74347d58a894be19c8988cdf1ee17126113eefc8d749782698",
        static_sha256 = "7d75ab07e54d4d71eccfe33821e4a9a7508ecac371f99bc341584f8d4798bb4c",
    )
    __static_shared_pair(
        mctx,
        name = "osxx86-64debug",
        shared_sha256 = "33f2e0f1a67c9555cc11970acd7e55fbcf2d3f45eb72e1b21430c24f8cbed894",
        static_sha256 = "764c70e143f3c79772c0a34bd61a0301384a5d9985ad43a80551ba9a30d3fbe0",
    )
    __static_shared_pair(
        mctx,
        name = "windowsx86-64debug",
        shared_sha256 = "353275e28d1b4bf093427b6e68889432c0c61974a14bc2372dc4455ccd44ab58",
        static_sha256 = "022d23a87f8c213a78fe5d50177c217cdd61f164990594952d83dc319454ab56",
    )
    __static_shared_pair(
        mctx,
        name = "windowsarm64debug",
        shared_sha256 = "ed79a7ca116caab00a1132ae8df6616ca9a43fe479493ac8bceb0026603e5d6c",
        static_sha256 = "f38c54484d42df69d723c431768b19cd01e25a42ad9384047f5b42523c0fa038",
    )

def setup_legacy_bzlmodrio_opencv_cpp_dependencies():
    __setup_bzlmodrio_opencv_cpp_dependencies(None)

setup_bzlmodrio_opencv_cpp_dependencies = module_extension(
    __setup_bzlmodrio_opencv_cpp_dependencies,
)
