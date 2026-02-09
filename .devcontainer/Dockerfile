FROM alpine:3 AS base-alpine

FROM base-alpine AS base

ENV BERKELEY_ABC_COMMIT=6339de7296c8c3b824ac6fc2ea0c44df06ffa5c2
ENV YOSYS_VERSION=0.62
ENV YOSYS_APICULA_VERSION=0.29
ENV YOSYS_NEXTPNR_COMMIT=master
ENV OFL_VERSION=1.0.0

RUN <<EOF
set -eux
apk add --no-cache \
    bash \
    boost-dev \
    eigen \
    font-noto \
    font-noto-extra \
    git \
    hidapi \
    libdw \
    libftdi1 \
    libgomp \
    libunwind \
    libusb \
    py3-numpy \
    py3-openpyxl \
    py3-pandas \
    py3-pillow \
    py3-pip \
    python3 \
    qt6-qtbase \
    tcl \
    vim \
    nano \
    xcb-util-cursor \
    zsh

pip3 install --no-cache-dir --break-system-packages crc
EOF
FROM base AS base-builder

RUN apk add --no-cache \
        autoconf \
        automake \
        bash \
        bison \
        build-base \
        cmake \
        eigen-dev \
        flex-dev \
        gawk \
        graphviz-dev \
	      hidapi-dev \
        libffi-dev \
        libftdi1-dev \
        libtool \
        libunwind-dev \
        libusb-dev \ 
        lld \
        ninja \ 
        protobuf-dev \
        py3-setuptools \
        qt6-qtbase-dev \
        readline-dev \
        tcl-dev \
        uv \
        wget \
        zlib-dev

WORKDIR /workspace

FROM base-builder AS abc-builder
RUN <<EOF
set -eux
mkdir -p abc
wget https://github.com/berkeley-abc/abc/archive/${BERKELEY_ABC_COMMIT}/abc-${BERKELEY_ABC_COMMIT}.tar.gz -O abc.tar.gz
tar -xf abc.tar.gz -C abc --strip-components=1
cd abc
make ABC_USE_PIC=1 ABC_USE_STDINT_H=1 -j$(nproc) abc 
make ABC_USE_PIC=1 ABC_USE_STDINT_H=1 -j$(nproc) libabc.so
make ABC_USE_PIC=1 ABC_USE_STDINT_H=1 -j$(nproc) libabc.a
EOF

FROM base-builder AS yosys-builder

ARG YOSYS_DESTDIR=/workspace/yosys-destdir

COPY --from=abc-builder --chmod=755 /workspace/abc/libabc.so /usr/lib/libabc.so
COPY --from=abc-builder --chmod=755 /workspace/abc/libabc.a /usr/lib/libabc.a
COPY --from=abc-builder --chmod=755 /workspace/abc/abc /usr/bin/abc

RUN <<EOF
set -eux
wget https://github.com/YosysHQ/yosys/releases/download/v${YOSYS_VERSION}/yosys.tar.gz
mkdir -p yosys
tar -xf yosys.tar.gz -C yosys
cd yosys
PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

cat > Makefile.conf << _EOF_
CONFIG:=gcc
PREFIX:=/usr
ABCEXTERNAL:=abc
BOOST_PYTHON_LIB:=-lpython${PYTHON_VERSION} -lboost_python${PYTHON_VERSION/./}
ENABLE_LIBYOSYS:=1
ENABLE_NDEBUG:=1
ENABLE_PROTOBUF:=1
ENABLE_PYOSYS:=1
ENABLE_ABC:=1
_EOF_
sed -i '/cp yosys-abc .*pyosys\/yosys-abc/d' Makefile

make CXX=g++ -j$(nproc)
make CXX=g++ DESTDIR="${YOSYS_DESTDIR}" install

EOF

FROM base-builder AS apicula-builder

ARG APICULA_DISTDIR=/workspace/apicula-dist
ARG GOWIN_DATADIR=/workspace/gowin-data

RUN <<EOF
set -eux
mkdir -p ${APICULA_DISTDIR} apicula ${GOWIN_DATADIR}

wget https://github.com/YosysHQ/apicula/releases/download/0.0.0.dev/linux-x64-gowin-data.tgz -O gowin-data.tgz
tar -xf gowin-data.tgz -C ${GOWIN_DATADIR}

git clone \
  --filter=blob:none \
  --no-checkout \
  https://github.com/YosysHQ/apicula.git apicula

cd apicula
git checkout "${YOSYS_APICULA_VERSION}"
git submodule update --init --recursive --depth=1

python setup.py build
python setup.py install --root="${APICULA_DISTDIR}" --optimize=1 --skip-build
cp -r ${GOWIN_DATADIR}/apycula ${APICULA_DISTDIR}/$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
EOF

FROM base-builder AS nextpnr-builder

ARG NEXTPNR_DESTDIR=/workspace/nextpnr-dist
ARG NEXTPNR_BUILDDIR=/workspace/nextpnr-build
COPY --from=apicula-builder --chmod=755 /workspace/apicula-dist/ /

RUN <<EOF
set -eux
mkdir -p ${NEXTPNR_BUILDDIR} ${NEXTPNR_DESTDIR} nextpnr
git clone \
  --filter=blob:none \
  --no-checkout \
  https://github.com/YosysHQ/nextpnr.git nextpnr

cd nextpnr
git checkout "${YOSYS_NEXTPNR_COMMIT}"
git submodule update --init --recursive --depth=1

rm -rf 3rdparty/corrosion
rm -rf himbaechel/uarch/xilinx/meta

sed -E -i 's/(Qt6 COMPONENTS)/\1 REQUIRED/' CMakeLists.txt
sed -E -i 's/\bsystem\b//g' CMakeLists.txt bba/CMakeLists.txt

cmake -B ${NEXTPNR_BUILDDIR} \
  -S . \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${NEXTPNR_DESTDIR}" \
  -DARCH="himbaechel" \
  -DBUILD_GUI=ON \
  -DUSE_IPO=OFF \
  -DUSE_OPENMP=ON \
  -DBUILD_TESTS=OFF \
  -DHIMBAECHEL_UARCH=gowin \
  -Wno-dev

cmake --build ${NEXTPNR_BUILDDIR} -j$(nproc)
cmake --install ${NEXTPNR_BUILDDIR}

EOF

FROM base-builder AS ofl-builder

ARG OFL_DESTDIR=/workspace/ofl-destdir

RUN <<EOF
set -eux
mkdir -p ${OFL_DESTDIR} ofl

wget https://github.com/trabucayre/openFPGALoader/archive/refs/tags/v${OFL_VERSION}.tar.gz -O ofl.tar.gz
tar -xf ofl.tar.gz -C ofl --strip-components=1

cd ofl

cmake -B build -G Ninja \
    -DBUILD_SHARED_LIBS=True \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_INSTALL_PREFIX=/ \
    -DCMAKE_INSTALL_LIBDIR=lib \
    
cmake --build build -j$(nproc)
DESTDIR="${OFL_DESTDIR}" cmake --install build

EOF

FROM base AS runtime

COPY --from=yosys-builder --chmod=755 /workspace/yosys-destdir/ /
COPY --from=abc-builder --chmod=755 /workspace/abc/libabc.so /usr/local/lib/libabc.so
COPY --from=abc-builder --chmod=755 /workspace/abc/libabc.a /usr/local/lib/libabc.a
COPY --from=abc-builder --chmod=755 /workspace/abc/abc /usr/local/bin/abc
COPY --from=apicula-builder --chmod=755 /workspace/apicula-dist/ /
COPY --from=nextpnr-builder --chmod=755 /workspace/nextpnr-dist/ /
COPY --from=ofl-builder --chmod=755 /workspace/ofl-destdir/ /usr/local/

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN <<EOF
set -eux
apk add --no-cache shadow sudo xauth jq zsh-theme-powerlevel10k
groupadd --gid $USER_GID $USERNAME
useradd --uid $USER_UID --gid $USER_GID  -s /bin/zsh -m $USERNAME
addgroup $USERNAME plugdev
addgroup $USERNAME dialout
echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME
chmod 0440 /etc/sudoers.d/$USERNAME
cat << EOM > /home/$USERNAME/.zshrc
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source /usr/share/zsh/plugins/powerlevel10k/powerlevel10k.zsh-theme
EOM
EOF

RUN <<EOF
set -eux
cat << 'EOM' > /usr/local/bin/build
#!/bin/bash
set -e

CONFIG_FILE="config.json"



get_config() {
    jq -r ".$1" "$CONFIG_FILE"
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: $CONFIG_FILE not found!"
        exit 1
    fi

    PROJECT_NAME=$(get_config "project_name")
    TOP_MODULE=$(get_config "top_module")
    CST_FILE=$(get_config "cst_file")
    DEVICE=$(get_config "device")
    SYNTH_FAMILY=$(get_config "synth_family")
    [ "$SYNTH_FAMILY" = "null" ] && SYNTH_FAMILY=""
    PNR_FAMILY=$(get_config "pnr_family")
    PACK_FAMILY=$(get_config "pack_family")
    BOARD=$(get_config "board")
}

resolve_sources() {
    RAW_SOURCES=$(jq -r '.sources[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    SOURCES=""
    for src in $RAW_SOURCES; do
        if [ -d "$src" ]; then
            FILES=$(find "$src" -name "*.v" | tr '\n' ' ')
            SOURCES="$SOURCES $FILES"
        elif [ -f "$src" ]; then
            SOURCES="$SOURCES $src"
        else
            echo "Warning: Source '$src' not found."
        fi
    done
}

synthesize() {
    resolve_sources
    echo ""
    echo "======================================"
    echo "        Step 1: Synthesis Process"
    echo "======================================"
    echo "Project: $PROJECT_NAME"
    echo "Sources: $SOURCES"
    echo "--------------------------------------"

    echo "[1/3] Synthesis (Yosys)..."
    FAMILY_ARG=""
    if [ -n "$SYNTH_FAMILY" ]; then
        FAMILY_ARG="-family $SYNTH_FAMILY"
    fi
    YOSYS_CMD="read_verilog $SOURCES; synth_gowin -top $TOP_MODULE -json ${PROJECT_NAME}.json $FAMILY_ARG"
    yosys -q -p "$YOSYS_CMD" || { echo "Synthesis failed!"; return 1; }

    echo "[2/3] Place & Route (Nextpnr)..."
    NEXTPNR_ARGS="--json ${PROJECT_NAME}.json --write ${PROJECT_NAME}_pnr.json --device $DEVICE --vopt family=$PNR_FAMILY --vopt cst=$CST_FILE"
    nextpnr-himbaechel $NEXTPNR_ARGS > /dev/null 2>&1 || { echo "PnR failed!"; return 1; }

    echo "[3/3] Packing (Gowin Pack)..."
    PACK_ARGS="-d $PACK_FAMILY -o ${PROJECT_NAME}.fs ${PROJECT_NAME}_pnr.json"
    gowin_pack $PACK_ARGS || { echo "Packing failed!"; return 1; }
    
    echo "--------------------------------------"
    echo "Synthesis Complete: ${PROJECT_NAME}.fs"
    echo "======================================"
}

flash() {
    echo ""
    echo "======================================"
    echo "        Step 2: Flash Process"
    echo "======================================"
    if [ ! -f "${PROJECT_NAME}.fs" ]; then
        echo "Error: ${PROJECT_NAME}.fs not found! Run synthesize first."
        return 1
    fi
    echo "Target Board: $BOARD"
    echo "Flashing ${PROJECT_NAME}.fs..."
    OFL_ARGS="-b $BOARD ${PROJECT_NAME}.fs"
    sudo openFPGALoader $OFL_ARGS || echo "Flashing failed (is the cable connected?)"
    echo "======================================"
}

while true; do
    load_config
    if [ -z "$1" ]; then
        echo "--------------------------------------"
        echo "Project: $PROJECT_NAME"
        echo "Board:   $BOARD"
        echo "--------------------------------------"
        echo "Select an action:"
        echo "1) Synthesize Only"
        echo "2) Flash Only"
        echo "3) Synthesize & Flash"
        echo "q) Quit"
        echo "--------------------------------------"
        read -p "Your choice [1-3, q]: " choice
        case $choice in
            1) STAGE="synthesize" ;;
            2) STAGE="flash" ;;
            3) STAGE="all" ;;
            q|Q) exit 0 ;;
            *) echo "Invalid choice"; continue ;;
        esac
    else
        STAGE=$1
    fi

    case $STAGE in
        synthesize|build)
            synthesize
            ;;
        flash)
            flash
            ;;
        all)
            synthesize && flash
            ;;
        *)
            echo "Usage: $0 {synthesize|flash|all}"
            exit 1
            ;;
    esac

    if [ -n "$1" ]; then
        break
    fi
done

exit 0
EOM
chmod a+x /usr/local/bin/build
EOF
USER $USERNAME
WORKDIR /home/$USERNAME/workspace
