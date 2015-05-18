Because bioinformatics pipelines typically consist of a bunch of independently
created applications running with various degrees of parallelism with differing
parallelization libraries, it is difficult to precisely profile their holistic
behavior at an application level with traditional tools like gprof.

This repository contains a set of very dirty scripts that profile the effect of
a pipeline at the systems level by polling the kernel with ps, iostat, and df
while a pipeline is running.  It also provides a few rudimentary scripts to
make parsing the resulting output data a little easier.
