# MapScript Ruby Bindings Setup

This document describes how MapServer with Ruby bindings (MapScript) was compiled and installed for this project.

## What is MapScript?

MapScript is a scripting interface to MapServer that allows you to generate map images, access WMS/WFS services, and manipulate map objects programmatically. This project requires it for the `wms` and `tile` endpoints in both `MapsController` and `LayersController`.

## Installation Summary

MapScript was compiled from source and installed on **October 6, 2025** with the following configuration:

- **MapServer Version**: 8.2.2
- **Ruby Version**: 3.4.5 (managed via rbenv)
- **Installation Location**:
  - Ruby bindings: `/Users/barnaclebarnes/.rbenv/versions/3.4.5/lib/ruby/site_ruby/3.4.0/arm64-darwin24/mapscript.bundle`
  - MapServer libraries: `~/mapserver/`

## Build Steps Performed

1. **Installed build dependencies via Homebrew:**

   ```bash
   brew install cmake swig
   brew install mapserver  # For required system libraries (GDAL, PROJ, GEOS, etc.)
   ```

2. **Cloned MapServer source:**

   ```bash
   cd /tmp/mapserver-build
   git clone https://github.com/MapServer/MapServer.git
   cd MapServer
   git checkout tags/rel-8-2-2 -b build-branch
   ```

3. **Configured build with CMake:**

   ```bash
   mkdir build && cd build
   cmake .. \
     -DCMAKE_INSTALL_PREFIX=$HOME/mapserver \
     -DWITH_RUBY=ON \
     -DRUBY_EXECUTABLE=$(which ruby) \
     -DRUBY_LIBRARY=$(ruby -e "puts RbConfig::CONFIG['libdir']")/libruby.dylib \
     -DRUBY_INCLUDE_DIR=$(ruby -e "puts RbConfig::CONFIG['rubyhdrdir']") \
     -DWITH_THREAD_SAFETY=ON \
     -DWITH_FCGI=OFF \
     -DWITH_POSTGIS=OFF \
     -DWITH_FRIBIDI=OFF \
     -DWITH_HARFBUZZ=OFF \
     -DWITH_CAIRO=ON \
     -DWITH_GEOS=ON \
     -DWITH_GDAL=ON \
     -DWITH_PROJ=ON
   ```

4. **Compiled and installed:**

   ```bash
   make -j$(sysctl -n hw.ncpu)
   make install
   ```

5. **Fixed library path (macOS specific):**
   ```bash
   install_name_tool -change @rpath/libmapserver.2.dylib \
     $HOME/mapserver/lib/libmapserver.2.dylib \
     ~/.rbenv/versions/$(rbenv version | cut -d' ' -f1)/lib/ruby/site_ruby/*/arm64-darwin*/mapscript.bundle
   ```

## Verification

To verify MapScript is working:

```bash
ruby -e "require 'mapscript'; puts Mapscript::MS_VERSION"
```

Expected output: `8.2.2`

## If You Upgrade Ruby

If you upgrade your Ruby version via rbenv, you'll need to recompile MapScript:

1. Switch to the new Ruby version: `rbenv global X.X.X`
2. Ensure Ruby was compiled with shared library support:
   ```bash
   ruby -e "puts RbConfig::CONFIG['ENABLE_SHARED']"
   ```
   (Should output `yes`)
3. Follow the build steps above again, including the library path fix in step 5

The MapScript bindings are specific to each Ruby version and must be recompiled for each Ruby installation.

## Dependencies

MapScript requires these system libraries (installed via Homebrew):

- GDAL (Geospatial Data Abstraction Library)
- PROJ (Cartographic projections library)
- GEOS (Geometry Engine)
- Cairo (2D graphics library)
- FreeType, LibPNG, LibJPEG

These are all managed by Homebrew and don't require recompilation when upgrading Ruby.

## Troubleshooting

### LoadError: cannot load such file -- mapscript

This means the Ruby bindings aren't in Ruby's load path. Verify:

```bash
ls ~/.rbenv/versions/$(rbenv version | cut -d' ' -f1)/lib/ruby/site_ruby/*/arm64-darwin*/mapscript.bundle
```

If missing, recompile MapScript following the build steps.

### Segmentation Fault

This usually indicates a version mismatch between MapScript and system libraries. Try:

```bash
brew upgrade gdal proj geos cairo
```

Then recompile MapScript.

## Code Changes Made

The following files were modified to use MapScript:

1. **app/controllers/maps_controller.rb**

   - Added `require 'mapscript'` and `include Mapscript` at class level
   - Implemented low-level caching for WMS and tile endpoints using `Rails.cache.fetch`
   - Removed deprecated `caches_action` calls

2. **app/controllers/layers_controller.rb**
   - Same changes as MapsController

## Additional Resources

- MapServer Documentation: https://mapserver.org/
- MapScript Ruby Documentation: https://mapserver.org/mapscript/ruby.html
- MapServer GitHub: https://github.com/MapServer/MapServer
