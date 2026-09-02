project ('com.github.gabutakut.gabutplayx', 'vala', 'c', version: '1.0.1')
gnome = import('gnome')
i18n = import('i18n')

cc = meson.get_compiler('c')

vapi = join_paths (meson.current_source_dir (), 'vapi')
add_global_arguments ('-DGETTEXT_PACKAGE="' + meson.project_name () + '"', language:'c')
add_global_arguments ('-DPACKAGE="' + meson.project_name () + '"', language:'c')
add_global_arguments ('-DVERSION="' + meson.project_name () + '"', language:'c')
add_project_arguments (['--vapidir', vapi], language: 'vala')

vala_args = ['--vapidir', vapi]

subdir ('src')
subdir ('data')
subdir ('po')
meson.add_install_script ('meson/post_install.py')