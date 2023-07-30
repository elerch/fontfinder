fontfinder
==========

Zig program to find fonts to solve my [mlterm](https://github.com/elerch/vcsh_mlterm)
font configuration problem. See https://github.com/elerch/vcsh_mlterm/blob/master/.mlterm/aafont
for more information on this.

See `fontfinder -h` for usage. For mlterm, you may want to use a different
pattern, specifically the default, but without spacing:

`-p :regular:normal:slant=0`

This was built with [Zig 0.11.0-dev.3886+0c1bfe271](https://github.com/marler8997/zig-unofficial-releases#0110-dev38860c1bfe271-summary).
The intent is to rebuild with Zig 0.11 when released, but the version above
is close enough that it should work at that time.

Building
========

This is not fully `zig build` friendly, since it links to system libraries.
Specifically, you need to have [fontconfig](https://www.freedesktop.org/wiki/Software/fontconfig/)
and dependencies installed. I initially went down that rabbit hole, but it's
kind of a mess that I don't need for what is really a personal project.

To help with the build, a Dockerfile exists in this repository that can be used
to create a docker image with the appropriate zig version and system libraries.
the shell script `zig-via-docker` will then act as a drop in replacement
for installed `zig`, passing all commands through to the container. That script
is set up for podman (same as docker, but allows running without root)
and a docker image named `fontfinder`.

This is a personal project, so happy for others to use it, but if you want things
to improve, you will need to file a PR. ;-)

