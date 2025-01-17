#!/bin/bash -eu
{ set +x; } 2>/dev/null
SOURCE="${BASH_SOURCE[0]}"
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

OS="Mac"
if [[ -e "/c/" ]]; then
  OS="Windows"
fi

PUBLIC=""
BUILD=0
NPM=0
UNITYVERSION=2019.2
BRANCHES=0
NUGET=0
VERSION=
PUBLIC=0

while (( "$#" )); do
  case "$1" in
    -p|--public)
      PUBLIC=1
    ;;
    -b|--build)
      BUILD=1
    ;;
    -u|--npm)
      NPM=1
    ;;
    -c|--branches)
      BRANCHES=1
    ;;
    -g|--nuget)
      NUGET=1
    ;;
    -g|--github)
      GITHUB=1
    ;;
    -v|--version)
      shift
      VERSION=$1
    ;;
    --ispublic)
      shift
      PUBLIC=$1
    ;;
    --trace)
      { set -x; } 2>/dev/null
    ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
    ;;
  esac
  shift
done

if [[ x"$VERSION" == x"" ]]; then
  VERSION=$(cat packageversion)
fi

function updateBranchAndPush() {
  local branch=$1
  local tag=$2
  local destdir=$3
  local pkgdir=$4
  local msg=$5
  local ver=$6
  local publ=$7

  echo "Publishing branch: $branch/latest ($VERSION)"

  pushd $destdir

  git reset --hard 38cb467e3d9d8b49f98019eee5cd463631d576a1
  git clean -xdf
  git reset --hard origin/$branch/latest >/dev/null 2>&1||true
  rm -rf *
  cp -R $pkgdir/* .
  git add .
  git commit -m "$msg"
  git tag $tag
  git push origin HEAD:$branch/latest
  git push origin $tag

  if [[ $publ -eq 1 ]]; then
      echo "Publishing branch: $branch/$VERSION"
      git push origin HEAD:$branch/$VERSION
  fi

  popd
}

if [[ x"$BRANCHES" == x"1" ]]; then
  srcdir=$DIR/build/packages
  destdir=$( cd .. >/dev/null 2>&1 && pwd )/branches
  test -d $destdir && rm -rf $destdir
  mkdir -p $destdir
  git clone -q --branch=empty git@github.com:spoiledcat/git-for-unity $destdir

  pushd $srcdir

  for name in *;do
    test -f $name/package.json || continue
    branch=packages/$name
    msg="$name v$VERSION"
    pkgdir=$srcdir/$name
    tag="$name-v$VERSION"

    updateBranchAndPush "$branch" "$tag" "$destdir" "$pkgdir" "$msg" "$VERSION" $PUBLIC

  done

  popd

fi

if [[ x"$NUGET" == x"1" ]]; then

  if [[ x"${PUBLISH_KEY:-}" == x"" ]]; then
    echo "Can't publish without a PUBLISH_KEY environment variable in the user:token format" >&2
    popd >/dev/null 2>&1
    exit 1
  fi

  if [[ x"${PUBLISH_URL:-}" == x"" ]]; then
    echo "Can't publish without a PUBLISH_URL environment variable" >&2
    popd >/dev/null 2>&1
    exit 1
  fi

  for p in "$DIR/build/nuget/**/*nupkg"; do
    dotnet nuget push $p -ApiKey "${PUBLISH_KEY}" -Source "${PUBLISH_URL}"
  done

fi

if [[ x"$NPM" == x"1" ]]; then

  #if in appveyor, only publish if public or in main
  if [[ x"${APPVEYOR:-}" != x"" ]]; then
    if [[ x"$PUBLIC" != x"1" ]]; then
      if [[ x"${APPVEYOR_PULL_REQUEST_NUMBER:-}" != x"" ]]; then
        echo "Skipping publishing non-public packages in CI on pull request builds"
        exit 0
      fi
      if [[ x"${APPVEYOR_REPO_BRANCH:-}" != x"main" ]]; then
        echo "Skipping publishing non-public packages in CI on pushes to branches other than main"
        exit 0
      fi
    fi
  fi

  if [[ x"${NPM_TOKEN:-}" == x"" ]]; then
    echo "Can't publish without a NPM_TOKEN environment variable" >&2
    popd >/dev/null 2>&1
    exit 1
  fi

  npm config set registry https://registry.spoiledcat.com
  npm config set //registry.spoiledcat.com/:_authToken $NPM_TOKEN
  npm config set always-auth true

  pushd build/npm
  for pkg in *.tgz;do
    npm publish -quiet $pkg
  done
  popd

  pushd upm-ci~/packages/
  for pkg in *.tgz;do
    npm publish -quiet $pkg
  done
  popd
fi
