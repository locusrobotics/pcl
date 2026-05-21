#!/bin/bash
#
# Build PCL as a Debian package installing libraries to /usr/local
#
set -e

PKG_NAME="libpcl-all-dev"
PKG_VERSION="1.13.1"
PKG_RELEASE="1"
UBUNTU_CODENAME="$(lsb_release -cs)"
INSTALL_PREFIX="/usr/local"
JOBS=$(nproc)

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SRC_DIR}/build_deb"
INSTALL_DIR="${BUILD_DIR}/install"
DEB_ROOT="${BUILD_DIR}/deb_root"

echo "=== Building PCL Debian package ==="
echo "  Source:  ${SRC_DIR}"
echo "  Prefix:  ${INSTALL_PREFIX}"
echo "  Jobs:    ${JOBS}"
echo ""

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${INSTALL_DIR}" "${DEB_ROOT}"

# Configure
echo "--- Configuring ---"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_CXX_STANDARD=14 \
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
Depends: libboost-all-dev, libeigen3-dev, libflann-dev, libqhull-dev, libusb-1.0-0-dev, libopenni2-0
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
if [ "$1" = "configure" ]; then
    ldconfig
fi
EOF

cat > "${DEB_ROOT}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ]; then
    ldconfig
fi
EOF

chmod 755 "${DEB_ROOT}/DEBIAN/postinst" "${DEB_ROOT}/DEBIAN/postrm"

# Ensure /usr/local/lib is in ldconfig search path
mkdir -p "${DEB_ROOT}/etc/ld.so.conf.d"
echo "${INSTALL_PREFIX}/lib" > "${DEB_ROOT}/etc/ld.so.conf.d/pcl.conf"

# Build the .deb
echo "--- Building .deb package ---"
DEB_FILE="${BUILD_DIR}/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}+${UBUNTU_CODENAME}_$(dpkg --print-architecture).deb"
dpkg-deb --build "${DEB_ROOT}" "${DEB_FILE}"

echo ""
echo "=== Done ==="
echo "Debian package: ${DEB_FILE}"
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${DEB_FILE}"
echo "  sudo apt-get install -f  # resolve any missing dependencies"
