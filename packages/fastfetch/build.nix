{ lib, pkgsStatic, cmake, pkg-config, pname }:
{ version, src, withThreads ? true }:
pkgsStatic.stdenv.mkDerivation {
  inherit pname version src;
  nativeBuildInputs = [ cmake pkg-config ];
  cmakeFlags = [
    "-DBINARY_LINK_TYPE=static"
    "-DIS_MUSL=ON"
    "-DSET_TWEAK=OFF"
    "-DENABLE_LTO=OFF"
    "-DENABLE_ZLIB=OFF"
    "-DCMAKE_INSTALL_SYSCONFDIR=etc"
  ] ++ map (feature: "-DENABLE_${feature}=OFF") [
    "VULKAN" "WAYLAND" "XCB_RANDR" "XCB" "XRANDR" "X11" "DRM"
    "GIO" "DCONF" "DBUS" "XFCONF" "SQLITE3" "RPM" "IMAGEMAGICK7"
    "IMAGEMAGICK6" "CHAFA" "EGL" "GLX" "OSMESA" "OPENCL" "FREETYPE"
    "PULSE" "DDCUTIL" "DIRECTX_HEADERS" "ELF" "LIBZFS"
  ] ++ [ ("-DENABLE_THREADS=" + (if withThreads then "ON" else "OFF")) ];
  meta = {
    description = "System information tool (portable static example)";
    homepage = "https://github.com/fastfetch-cli/fastfetch";
    license = lib.licenses.mit;
    mainProgram = "fastfetch";
    platforms = import ./systems.nix;
  };
}
