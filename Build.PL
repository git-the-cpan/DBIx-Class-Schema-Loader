use strict;
use Module::Build;

my %arguments = (
    license            => 'perl',
    module_name        => 'DBIx::Class::Schema::Loader',
    requires           => {
        'DBIx::Class'                   => 0.06,
        'UNIVERSAL::require'            => 0.10,
        'Lingua::EN::Inflect::Number'   => 1.1,
        'Text::Balanced'                => 0,
        'Class::Accessor::Fast'         => 0.22,
        'Class::Data::Accessor'         => 0.02,
        'Class::C3'                     => 0.11,
    },
    recommends         => {
        'Class::Inspector'              => 0
    },
    build_requires     => {
        'Test::More'                    => 0.32,
        'DBI'                           => 1.50,
        'DBD::SQLite'                   => 1.11,
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
);

# The idea here is to recommend an upgrade of the DBD only
#  if they have some existing version installed.
my %dbd_recs = (
    'DBD::SQLite' => 1.11,
    'DBD::mysql'  => 3.0002,
    'DBD::Pg'     => 1.45,
    'DBD::DB2'    => 0.78,
);

foreach my $dbd (keys %dbd_recs) {
    eval "require $dbd";
    $arguments{recommends}->{$dbd} = $dbd_recs{$dbd} if !$@;
}

Module::Build->new(%arguments)->create_build_script;
