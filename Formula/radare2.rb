class CodesignRequirement < Requirement
  fatal true

  satisfy(:build_env => false) do
    FileUtils.mktemp do
      FileUtils.cp "/usr/bin/false", "radare2_check"
      quiet_system "/usr/bin/codesign", "-f", "-s", "org.radare.radare2", "--dryrun", "radare2_check"
    end
  end

  def message
    <<~EOS
      org.radare.radare2 identity must be available to build with automated signing.
      See: https://github.com/radare/radare2/blob/master/doc/macos.md
    EOS
  end
end

class Radare2 < Formula
  desc "Reverse engineering framework"
  homepage "https://radare.org"

  stable do
    url "https://radare.mikelloc.com/get/2.5.0/radare2-2.5.0.tar.gz"
    sha256 "6713f8895fdb7855f7c28a36b14b8e17b383f0664d74122b8a0e2a8c8b5a049e"

    resource "bindings" do
      url "https://radare.mikelloc.com/get/2.5.0/radare2-bindings-2.5.0.tar.gz"
      sha256 "f01e1530504a9d52a2ad21edbebb9b68c560b026e35fff406124947b1ea9d483"
    end

    resource "extras" do
      url "https://radare.mikelloc.com/get/2.5.0/radare2-extras-2.5.0.tar.gz"
      sha256 "dc7ec28cbbf0a5d3afd246f9a9d7341c4df8cf77c2719119e9294ba95ea2aad8"

      # Remove for > 2.5.0
      # Fix "ld: library not found for -lr_reg"
      # Upstream commit from 11 Apr 2018 "x86_udis.mk: also pass LDFLAGS"
      patch do
        url "https://github.com/radare/radare2-extras/commit/8cce5eb.patch?full_index=1"
        sha256 "b02e7019ab963e5ec975997436a900b512c7cebf8652d2d7ecfa4772842a5215"
      end
    end
  end

  bottle do
    sha256 "709aaeec51c7353513b4c36cc7ecc6f6b2dedc0699d9624a8aeeefd375628fa9" => :high_sierra
    sha256 "94c59eae264417039adbd4c0b0d532cd16561d525d6554a73b1eef807e1b6ba0" => :sierra
    sha256 "4d1c3880ac23043098dfc812443f00b02f426781f262317a36b1bde0e417f835" => :el_capitan
  end

  head do
    url "https://github.com/radare/radare2.git"

    resource "bindings" do
      url "https://github.com/radare/radare2-bindings.git"
    end

    resource "extras" do
      url "https://github.com/radare/radare2-extras.git"
    end
  end

  option "with-code-signing", "Codesign executables to provide unprivileged process attachment"

  depends_on "pkg-config" => :build
  depends_on "valabind" => :build
  depends_on "swig" => :build
  depends_on "gobject-introspection" => :build
  depends_on "gmp"
  depends_on "jansson"
  depends_on "libewf"
  depends_on "libmagic"
  depends_on "lua"
  depends_on "openssl"
  depends_on "yara"

  depends_on CodesignRequirement if build.with? "code-signing"

  def install
    # Build Radare2 before bindings, otherwise compile = nope.
    system "./configure", "--prefix=#{prefix}", "--with-openssl"
    system "make", "CS_PATCHES=0"
    if build.with? "code-signing"
      # Brew changes the HOME directory which breaks codesign
      home = `eval printf "~$USER"`
      system "make", "HOME=#{home}", "-C", "binr/radare2", "macossign"
      system "make", "HOME=#{home}", "-C", "binr/radare2", "macos-sign-libs"
    end
    ENV.deparallelize { system "make", "install" }

    # remove leftover symlinks
    # https://github.com/radare/radare2/issues/8688
    rm_f bin/"r2-docker"
    rm_f bin/"r2-indent"

    resource("extras").stage do
      ENV.append_path "PATH", bin
      ENV.append_path "PKG_CONFIG_PATH", "#{lib}/pkgconfig"

      system "./configure", "--prefix=#{prefix}"
      system "make", "all"
      system "make", "install"
    end

    resource("bindings").stage do
      ENV.append_path "PATH", bin
      ENV.append_path "PKG_CONFIG_PATH", "#{lib}/pkgconfig"

      # Language versions.
      perl_version = `/usr/bin/perl -e 'printf "%vd", $^V;'`
      lua_version = Formula["lua"].version.to_s.match(/\d\.\d/)

      # Lazily bind to Python.
      inreplace "do-swig.sh", "VALABINDFLAGS=\"\"", "VALABINDFLAGS=\"--nolibpython\""
      make_binding_args = ["CFLAGS=-undefined dynamic_lookup"]

      # Ensure that plugins and bindings are installed in the correct Cellar
      # paths.
      inreplace "libr/lang/p/Makefile", "R2_PLUGIN_PATH=", "#R2_PLUGIN_PATH="
      # fix build, https://github.com/radare/radare2-bindings/pull/168
      inreplace "libr/lang/p/Makefile",
      "CFLAGS+=$(shell pkg-config --cflags r_core)",
      "CFLAGS+=$(shell pkg-config --cflags r_core) -DPREFIX=\\\"${PREFIX}\\\""
      inreplace "Makefile", "LUAPKG=", "#LUAPKG="
      inreplace "Makefile", "${DESTDIR}$$_LUADIR", "#{lib}/lua/#{lua_version}"
      make_install_args = %W[
        R2_PLUGIN_PATH=#{lib}/radare2/#{version}
        LUAPKG=lua-#{lua_version}
        PERLPATH=#{lib}/perl5/site_perl/#{perl_version}
        PYTHON_PKGDIR=#{lib}/python2.7/site-packages
        RUBYPATH=#{lib}/ruby/#{RUBY_VERSION}
      ]

      system "./configure", "--prefix=#{prefix}"
      ["lua", "perl", "python"].each do |binding|
        system "make", "-C", binding, *make_binding_args
      end
      system "make"
      system "make", "install", *make_install_args
    end
  end

  test do
    assert_match "radare2 #{version}", shell_output("#{bin}/r2 -version")
  end
end
