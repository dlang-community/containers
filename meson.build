project('dcontainers', 'd',
    meson_version: '>=0.46',
    license: 'BSL-1.0',
    version: '0.8.0'
)

project_soversion = '0'
stdx_allocator_dep = dependency('stdx-allocator', fallback : ['stdx-allocator', 'stdx_allocator_dep'])

required_deps = [stdx_allocator_dep]

#
# Sources
#
dcontainers_src = [
    'src/containers/cyclicbuffer.d',
    'src/containers/dynamicarray.d',
    'src/containers/hashmap.d',
    'src/containers/hashset.d',
    'src/containers/immutablehashset.d',
    'src/containers/internal/backwards.d',
    'src/containers/internal/element_type.d',
    'src/containers/internal/hash.d',
    'src/containers/internal/mixins.d',
    'src/containers/internal/node.d',
    'src/containers/internal/storage_type.d',
    'src/containers/openhashset.d',
    'src/containers/package.d',
    'src/containers/simdset.d',
    'src/containers/slist.d',
    'src/containers/treemap.d',
    'src/containers/ttree.d',
    'src/containers/unrolledlist.d'
]

src_dir = include_directories('src/')

#
# Targets
#
dcontainers_lib = both_libraries('dcontainers',
        [dcontainers_src],
        include_directories: [src_dir],
        install: true,
        version: meson.project_version(),
        soversion: project_soversion,
        dependencies: required_deps
)

pkgc = import('pkgconfig')
pkgc.generate(name: 'dcontainers',
              libraries: [dcontainers_lib],
              subdirs: 'd/containers',
              version: meson.project_version(),
              description: 'Containers backed by std.experimental.allocator.'
)

# for use by others which embed this as subproject
dcontainers_dep = declare_dependency(
    link_with: [dcontainers_lib],
    include_directories: [src_dir],
)

#
# Tests
#
extra_args = ['-main']

dcontainers_test_exe = executable('test_dcontainers',
    [dcontainers_src,
    'test/compile_test.d',
    'test/external_allocator_test.d'],
    include_directories: [src_dir],
    d_unittest: true,
    link_args: extra_args
)
test('test_dcontainers', dcontainers_test_exe)

# the looptest is a manual test, so we don't run it and only compile it
looptest_test_exe = executable('test_looptest',
    ['test/looptest.d'],
    dependencies: [dcontainers_dep]
)

#
# Install
#
install_subdir('src/containers/', install_dir: 'include/d/containers/')
