package DBIx::Class::Schema::Loader::DBI::mysql;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Class::C3;

=head1 NAME

DBIx::Class::Schema::Loader::DBI::mysql - DBIx::Schema::Class::Loader mysql Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->load_from_connection(
    relationships => 1,
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _table_fk_info {
    my ($self, $table) = @_;

    my $dbh    = $self->schema->storage->dbh;

    my $query = "SHOW CREATE TABLE ${table}";
    my $sth   = $dbh->prepare($query)
      or die("Cannot get table definition: $table");
    $sth->execute;
    my $table_def = $sth->fetchrow_arrayref->[1] || '';
    $sth->finish;
    
    my (@reldata) = ($table_def =~ /CONSTRAINT `.*` FOREIGN KEY \(`(.*)`\) REFERENCES `(.*)` \(`(.*)`\)/ig);

    my @rels;
    while (scalar @reldata > 0) {
        my $cols = shift @reldata;
        my $f_table = shift @reldata;
        my $f_cols = shift @reldata;

        my @cols = map { s/\Q$self->{_quoter}\E//; lc $_ } split(/\s*,\s*/,$cols);
        my @f_cols = map { s/\Q$self->{_quoter}\E//; lc $_ } split(/\s*,\s*/,$f_cols);

        push(@rels, {
            local_columns => \@cols,
            remote_columns => \@f_cols,
            remote_table => $f_table
        });
    }

    return \@rels;
}

# primary and unique info comes from the same sql statement,
#   so cache it here for both routines to use
sub _mysql_table_get_keys {
    my ($self, $table) = @_;

    if(!exists($self->{_mysql_keys}->{$table})) {
        my %keydata;
        my $dbh = $self->schema->storage->dbh;
        my $sth = $dbh->prepare("SHOW INDEX FROM $table");
        $sth->execute;
        while(my $row = $sth->fetchrow_hashref) {
            next if $row->{Non_unique};
            push(@{$keydata{$row->{Key_name}}},
                [ $row->{Seq_in_index}, lc $row->{Column_name} ]
            );
        }
        foreach my $keyname (keys %keydata) {
            my @ordered_cols = map { $_->[1] } sort { $a->[0] <=> $b->[0] }
                @{$keydata{$keyname}};
            $keydata{$keyname} = \@ordered_cols;
        }
        $self->{_mysql_keys}->{$table} = \%keydata;
    }

    return $self->{_mysql_keys}->{$table};
}

sub _table_pk_info {
    my ( $self, $table ) = @_;

    return $self->_mysql_table_get_keys($table)->{PRIMARY};
}

sub _table_uniq_info {
    my ( $self, $table ) = @_;

    my @uniqs;
    my $keydata = $self->_mysql_table_get_keys($table);
    foreach my $keyname (%$keydata) {
        next if $keyname eq 'PRIMARY';
        push(@uniqs, [ $keyname => $keydata->{$keyname} ]);
    }

    return \@uniqs;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=cut

1;
