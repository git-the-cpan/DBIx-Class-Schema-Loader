package DBIx::Class::Schema::Loader::DBI::Pg;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Class::C3;

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Pg - DBIx::Class::Schema::Loader Postgres Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->connection(
    dsn       => "dbi:Pg:dbname=dbname",
    user      => "postgres",
    password  => "",
  );

  __PACKAGE__->load_from_connection(
    relationships => 1,
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=head1 METHODS

=head2 load

Overlays L<DBIx::Class::Schema::Loader::Base>'s C<load()> to default the postgres
schema to C<public> rather than blank.

=cut

sub load {
    my $self = shift;

    $self->{db_schema} ||= 'public';

    $self->next::method(@_);
}

sub _tables {
    my $self = shift;
    my $dbh = $self->schema->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};

    # This is split out to avoid version parsing errors...
    my $is_dbd_pg_gte_131 = ( $DBD::Pg::VERSION >= 1.31 );
    my @tables = $is_dbd_pg_gte_131
        ?  $dbh->tables( undef, $self->db_schema, "",
                         "table", { noprefix => 1, pg_noprefix => 1 } )
        : $dbh->tables;

    s/$quoter//g for @tables;
    return @tables;
}

sub _table_info {
    my ( $self, $table ) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};

    my $sth = $dbh->column_info(undef, $self->db_schema, $table, undef);
    my @cols = map { $_->[3] } @{ $sth->fetchall_arrayref };
    s/$quoter//g for @cols;
    
    my @primary = $dbh->primary_key(undef, $self->db_schema, $table);

    s/$quoter//g for @primary;

    return ( \@cols, \@primary );
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
