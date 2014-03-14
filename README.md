job2package tool for cf-relase
===

This script is used to confvert [cf-release](https://github.com/cloudfoundry/cf-release) jobs to sources that can be used in packages. There is no magic there at all. Just converting ERB templates of given job to files with [default values](https://github.com/Altoros/cf-job2package-tool/blob/master/build.rb#L121-L150).

Usage
---
```
./build.rb <job dir> <output dir>
```
Example: `./build.rb ~/work/github/cf-release/jobs/nats ~/some-workspace-with-package-sources`
