# Things I need to do for the Ray Tracer

* Implement BVH
* Fix race conditions when updating the ray statistics with multiple threads
* Add verbose option
* Add support for shapes in groups in yaml file
* Create .yaml scene descriptions for the existing demos
* Modify the CLI options to remove demos and leave only .yaml scene descriptions
* Add --out <filename> option
* Test all scene desciptions from lerouxrgd
* Restructure directory and/or remove JavaScript implementation, leaving only Zig and Go
* Push to Github
* Support multiple point lights

# Done

* Accept both .yml and .yaml file extensions
* Move to Zig 0.17.0
* Move readObjFile to a separate file
* Add support for PI/n in parseFloat (yaml.zig)
* Pass material to readObjFile()
* Move Material to material.zig
* Skip blanks in readTransform()
* Use proper stdio instead of std.debug.print
* Add statistics for number or rays traced during rendering
* Set correct line numbers in struct LevelLine
* Initialize git versioning

