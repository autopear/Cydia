#!/bin/bash
ver=$(git describe --tags --dirty="+")
ver=${ver#v}
ver=${ver//-/.}
echo "${ver}"
