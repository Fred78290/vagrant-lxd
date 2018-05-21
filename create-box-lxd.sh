#!/bin/bash

. setenv.sh

function build_box {
BOXFILE="$1"
BOXNAME="$2"
BOXVERSION="$3"
BOXDESCRIPTION="$4"
PUSHFTP="$5"

DIRBOX=$(echo $BOXNAME | sed -e 's/\//-VAGRANTSLASH-/g')

echo
echo "Create box LXD $BOXNAME"

mkdir -p $VAGRANT_BOX_BUILDDIR

pushd $VAGRANT_BOX_BUILDDIR

rm -rf $DIRBOX || true
mkdir -p $DIRBOX/build

pushd $DIRBOX/build

echo "Delete previous LXD image $BOXNAME"
lxc image delete $BOXNAME

echo "Publish LXD image $BOXFILE --> $BOXNAME"
lxc publish $BOXFILE --alias "$BOXNAME" --force description="$BOXDESCRIPTION" version="$BOXVERSION"

FINGERPRINT=$(lxc image info "$BOXNAME" | awk '/^Fingerprint/' | awk '{print $2}')

echo "Export LXD image $BOXNAME"
lxc image export "$BOXNAME" rootfs

echo "Prepare metadata for LXD image $BOXNAME, fingerprint:$FINGERPRINT"
gunzip -c rootfs.tar.gz | tar -xf - metadata.yaml
mv metadata.yaml lxd_metadata.yaml
ex -sc "3i|source_fingerprint: $FINGERPRINT" -cx lxd_metadata.yaml

cat > metadata.json <<EOF
{
  "name": "$BOXNAME",
  "provider": "lxc",
  "description": "$BOXDESCRIPTION",
  "version": "$BOXVERSION"
}
EOF

echo "Create box archive $DIRBOX"
tar zcvf ../$DIRBOX-$BOXVERSION-lxd.box ./*
popd


# Shasum
lxd_sha1sum=`sha1sum $DIRBOX/$DIRBOX-$BOXVERSION-lxd.box | awk '{ print $1 }'`

cat > $DIRBOX/$DIRBOX-lxd.json <<EOF
{
  "name": "$BOXNAME",
  "description": "$BOXDESCRIPTION",
  "versions": [
    {
      "version": "$BOXVERSION",
      "providers": [
        {
          "name": "lxc",
          "url": "${VAGRANT_BOX_SERVER}${DIRBOX}-${BOXVERSION}-lxd.box",
          "checksum_type": "sha1",
          "checksum": "$lxd_sha1sum"
        }
      ]
    }
  ]
}
EOF

cat > $DIRBOX/$DIRBOX-local-lxd.json <<EOF
{
  "name": "$BOXNAME",
  "description": "$BOXDESCRIPTION",
  "versions": [
    {
      "version": "$BOXVERSION",
      "providers": [
        {
          "name": "lxc",
          "url": "file://$VAGRANT_BOX_BUILDDIR/$DIRBOX/$DIRBOX-$BOXVERSION-lxd.box",
          "checksum_type": "sha1",
          "checksum": "$lxd_sha1sum"
        }
      ]
    }
  ]
}
EOF

if [ "$PUSHFTP" = "YES" ]; then
  echo "Transfer $DIRBOX-$BOXVERSION-lxd.box"
  curl -T $VAGRANT_BOX_BUILDDIR/$DIRBOX/$DIRBOX-$BOXVERSION-lxd.box "ftp://$VAGRANT_FTP_UID:$VAGRANT_FTP_PWD@$VAGRANT_FTP_SERVER/$VAGRANT_FTP_DIR"
  echo "Transfer $DIRBOX-$BOXVERSION-lxd.json"
  curl -T $VAGRANT_BOX_BUILDDIR/$DIRBOX/$DIRBOX-lxd.json "ftp://$VAGRANT_FTP_UID:$VAGRANT_FTP_PWD@$VAGRANT_FTP_SERVER/$VAGRANT_FTP_DIR"
fi

vagrant box remove $BOXNAME --provider=lxc
vagrant box add $VAGRANT_BOX_BUILDDIR/$DIRBOX/$DIRBOX-local-lxd.json --provider=lxc
}

build_box "$1" "$2" "$3" "$4" "$5"
