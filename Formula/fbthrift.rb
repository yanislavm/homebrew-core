class Fbthrift < Formula
  desc "Facebook's branch of Apache Thrift, including a new C++ server"
  homepage "https://github.com/facebook/fbthrift"
  url "https://github.com/facebook/fbthrift/archive/v2023.01.02.00.tar.gz"
  sha256 "fa8df52262268e97cbc349b18ad686bec2ecb56ceb3774e2475f947adea41178"
  license "Apache-2.0"
  head "https://github.com/facebook/fbthrift.git", branch: "main"

  bottle do
    sha256 cellar: :any,                 arm64_ventura:  "70a9eb023d5145e746c9c057ab7767dd61b9c316843a45e51aa61baabaf19209"
    sha256 cellar: :any,                 arm64_monterey: "aacbe4363e979d6c4f1297bdf736fd61934fb4ca2b4df8f3665525c6a3a3173e"
    sha256 cellar: :any,                 arm64_big_sur:  "2701b265b73d70bf1b518dbf05ce90f5b12c252e996671285fad797ad4846960"
    sha256 cellar: :any,                 ventura:        "41e0795017b15160e722d2cd5ef10ecaf4dbd6ddac8f3af4e3b6749fdbb1908e"
    sha256 cellar: :any,                 monterey:       "7a67df9f02a3160974e221b56b0cfec3c5b0332793b4004d720d7aaeab2c9bec"
    sha256 cellar: :any,                 big_sur:        "b2ca20734760f342c7c7f32e132d073fabc56331cfa8f534c1a9d312f5edddac"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "bbba4934c438af6adc893d8fc6095d66e6b6c83e43ad6da5c0583e0488b8b1da"
  end

  depends_on "bison" => :build # Needs Bison 3.1+
  depends_on "cmake" => :build
  depends_on "boost"
  depends_on "fizz"
  depends_on "fmt"
  depends_on "folly"
  depends_on "gflags"
  depends_on "glog"
  depends_on "openssl@1.1"
  depends_on "wangle"
  depends_on "zstd"

  uses_from_macos "flex" => :build
  uses_from_macos "zlib"

  on_macos do
    depends_on "llvm" if DevelopmentTools.clang_build_version <= 1100
  end

  fails_with :clang do
    build 1100
    cause <<~EOS
      error: 'asm goto' constructs are not supported yet
    EOS
  end

  fails_with gcc: "5" # C++ 17

  def install
    ENV.llvm_clang if OS.mac? && (DevelopmentTools.clang_build_version <= 1100)

    # The static libraries are a bit annoying to build. If modifying this formula
    # to include them, make sure `bin/thrift1` links with the dynamic libraries
    # instead of the static ones (e.g. `libcompiler_base`, `libcompiler_lib`, etc.)
    shared_args = ["-DBUILD_SHARED_LIBS=ON", "-DCMAKE_INSTALL_RPATH=#{rpath}"]
    shared_args << "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-undefined,dynamic_lookup" if OS.mac?

    system "cmake", "-S", ".", "-B", "build/shared", *std_cmake_args, *shared_args
    system "cmake", "--build", "build/shared"
    system "cmake", "--install", "build/shared"

    elisp.install "thrift/contrib/thrift.el"
    (share/"vim/vimfiles/syntax").install "thrift/contrib/thrift.vim"
  end

  test do
    (testpath/"example.thrift").write <<~EOS
      namespace cpp tamvm

      service ExampleService {
        i32 get_number(1:i32 number);
      }
    EOS

    system bin/"thrift1", "--gen", "mstch_cpp2", "example.thrift"
    assert_predicate testpath/"gen-cpp2", :exist?
    assert_predicate testpath/"gen-cpp2", :directory?
  end
end
