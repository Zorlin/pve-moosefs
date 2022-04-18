#!/bin/bash
# Pull in latest changes from git, make the package and install it.
git pull && rm *.deb && make && dpkg -i *.deb