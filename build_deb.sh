#!/bin/bash
#
# Build PCL as a Debian package.
# The install prefix defaults to /usr but can be overridden via INSTALL_PREFIX env var.
#
set -e

usage() {
    echo "Usage: $0 [-j|--jobs <N>]"
    echo ""
    echo "  -j, --jobs <N>   Number of parallel compile jobs (default: all cores via nproc)"
    echo "                   Can also be set via the JOBS environment variable."
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j|--jobs)
            [[ -z "${2:-}" || ! "${2}" =~ ^[1-9][0-9]*$ ]] && { echo "Error: --jobs requires a positive integer"; usage; }
            JOBS="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

PKG_NAME="libpcl-all-dev"
PKG_VERSION="1.13.1"
PKG_RELEASE="1"
UBUNTU_CODENAME="$(lsb_release -cs)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr}"
JOBS="${JOBS:-$(nproc)}"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SRC_DIR}/build_deb"
DEB_ROOT="${BUILD_DIR}/deb_root"

echo "=== Building PCL Debian package ==="
echo "  Source:  ${SRC_DIR}"
echo "  Prefix:  ${INSTALL_PREFIX}"
echo "  Jobs:    ${JOBS}"
echo ""

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${DEB_ROOT}"

# Configure
echo "--- Configuring ---"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_CXX_FLAGS='-O3 -g1 -DNDEBUG -march=haswell -fext-numeric-literals -DBOOST_BIND_GLOBAL_PLACEHOLDERS -DBOOST_ALLOW_DEPRECATED_HEADERS' \
    -DCMAKE_CXX_STANDARD='17' \
    -DCMAKE_CXX_STANDARD_REQUIRED='ON' \
    -DCMAKE_CXX_EXTENSIONS='ON' \
    -DBUILD_tools=OFF \
    -DBUILD_examples=OFF \
    -DBUILD_apps=OFF \
    -DBUILD_simulation=OFF \
    -DBUILD_global_tests=OFF \
    -DWITH_CUDA=OFF \
    -DWITH_OPENGL=OFF \
    -DWITH_QT=OFF \
    -DWITH_VTK=OFF \
    -DWITH_PCAP=OFF

# Build
echo "--- Building ---"
cmake --build "${BUILD_DIR}" --parallel "${JOBS}"

# Install to staging directory
echo "--- Installing to staging area ---"
DESTDIR="${DEB_ROOT}" cmake --install "${BUILD_DIR}"

# Create Debian control file
INSTALLED_SIZE=$(du -sk "${DEB_ROOT}" | cut -f1)
mkdir -p "${DEB_ROOT}/DEBIAN"

cat > "${DEB_ROOT}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}-${PKG_RELEASE}+${UBUNTU_CODENAME}
Section: libs
Priority: optional
Architecture: $(dpkg --print-architecture)
Installed-Size: ${INSTALLED_SIZE}
Depends: libboost-all-dev, libeigen3-dev, libflann-dev, libqhull-dev, libusb-1.0-0-dev, libopenni2-0, libopenni0
Maintainer: Gary Servin <gservin@locusrobotics.com>
Description: Point Cloud Library (PCL) - development files
 The PCL framework contains numerous state-of-the-art algorithms including
 filtering, feature estimation, surface reconstruction, registration, model
 fitting and segmentation. Libraries are installed to ${INSTALL_PREFIX}.
EOF

# Add ldconfig trigger
cat > "${DEB_ROOT}/DEBIAN/triggers" <<EOF
activate-noawait ldconfig
EOF

# Create postinst/postrm for ldconfig
cat > "${DEB_ROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
#DEBHELPER#
EOF

cat > "${DEB_ROOT}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
#DEBHELPER#
EOF

chmod 755 "${DEB_ROOT}/DEBIAN/postinst" "${DEB_ROOT}/DEBIAN/postrm"

# Ensure /usr/local/lib is in ldconfig search path
mkdir -p "${DEB_ROOT}/etc/ld.so.conf.d"
echo "${INSTALL_PREFIX}/lib" > "${DEB_ROOT}/etc/ld.so.conf.d/pcl.conf"

# Build the .deb
echo "--- Building .deb package ---"
DEB_FILE="${BUILD_DIR}/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}+${UBUNTU_CODENAME}_$(dpkg --print-architecture).deb"
dpkg-deb --root-owner-group --build "${DEB_ROOT}" "${DEB_FILE}"

echo ""
echo "=== Done ==="
echo "Debian package: ${DEB_FILE}"
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${DEB_FILE}"
echo "  sudo apt-get install -f  # resolve any missing dependencies"
