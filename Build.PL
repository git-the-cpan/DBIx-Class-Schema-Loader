use strict;
use Module::Build;

# XXX
warn "---- Requires branches/DBIx-Class-current installed ----";

my %arguments = (
    license            => 'perl',
    module_name        => 'DBIx::Class::Schema::Loader',
    requires           => {
        'DBIx::Class'                   => 0.06, # XXX or whatever -current becomes with the PK::Auto change
        'UNIVERSAL::require'            => 0.10,
        'Lingua::EN::Inflect::Number'   => 1.1,
        'Text::Balanced'                => 0,
        'Class::Accessor::Fast'         => 0.22,
        'Class::Data::Accessor'         => 0.02,
        'Class::C3'                     => 0.09,
    },
    build_requires     => {
        'Test::More'          => 0.32,
        'DBI'                 => 1.50,
        'DBD::SQLite'         => 1.11,
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
);

Module::Build->new(%arguments)->create_build_script;
