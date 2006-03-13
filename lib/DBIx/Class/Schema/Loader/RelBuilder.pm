package DBIx::Class::Schema::Loader::RelBuilder;

use strict;
use warnings;
use Carp;
use Lingua::EN::Inflect::Number ();

=head1 NAME

DBIx::Class::Schema::Loader::RelBuilder - Builds relationships for DBIx::Class::Schema::Loader

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader>

=head1 DESCRIPTION

This class builds relationships for L<DBIx::Class::Schema::Loader>.  This
is module is not (yet) for external use.

=head1 METHODS

=head2 new

Arguments: schema_class (scalar), fk_info (hashref) [, inflect_map ]

C<$schema_class> should be a schema class name, where the source
classes have already been set up and registered.  Column info, primary
key, and unique constraints will be drawn from this schema for all
of the existing source monikers.

The fk_info hashref's contents should take the form:

  {
      TableMoniker => [
          {
              local_columns => [ 'col2', 'col3' ],
              remote_columns => [ 'col5', 'col7' ],
              remote_moniker => 'AnotherTableMoniker',
          },
          # ...
      ],
      AnotherTableMoniker => [
          # ...
      ],
      # ...
  }

And inflect_map is documented at L<DBIx::Class::Schema::Loader>, either a coderef
or a hashref which can override the default L<Lingua::EN::Inflect::Number>
pluralizations.  Used in generating relationship names.

=head2 generate_code

This method will return the generated relationships as a hashref per table moniker,
containing an arrayref of code strings which can be "eval"-ed in the context of
the source class, like:

  {
      'Some::Source::Class' => [
          "belongs_to( col1 => 'AnotherTableMoniker' )",
          "has_many( anothers => 'AnotherTableMoniker', 'col15' )",
      ],
      'Another::Source::Class' => [
          # ...
      ],
      # ...
  }
          
You might want to use this in building an on-disk source class file, by
adding each string to the appropriate source class file,
prefixed by C<__PACKAGE__-E<gt>>.

=head2 setup_rels

Arguments: debug (boolean)

Basically, calls L<#generate_code>, and then evals the generated code in
the appropriate class context, all in one fell swoop.  This is how Schema::Loader
uses this class.  Will dump the strings to stderr along the way if C<$debug> is
set.

=cut

sub new {
    my ( $class, $schema, $fk_info, $inflect_map ) = @_;

    my $self = {
        schema => $schema,
        fk_info => $fk_info,
        inflect_map => $inflect_map,
    };

    bless $self => $class;

    $self;
}

# Inflect a relationship name
sub _inflect_relname {
    my ($self, $relname) = @_;

    if( ref $self->{inflect_map} eq 'HASH' ) {
        return $self->{inflect_map}->{$relname}
            if exists $self->{inflect_map}->{$relname};
    }
    elsif( ref $self->{inflect_map} eq 'CODE' ) {
        my $inflected = $self->{inflect_map}->($relname);
        return $inflected if $inflected;
    }

    return Lingua::EN::Inflect::Number::to_PL($relname);
}

# XXX this is all horribly broken in implementation at the moment,
#  and nothing like the real thing should be.  It's just here so
#  I can run tests and validate some other basic crap.
sub generate_code {
    my $self = shift;

    my $all_code = {};

    foreach my $moniker (keys %{$self->{fk_info}}) {
       my $rels = $self->{fk_info}->{$moniker};
       my $local_obj = $self->{schema}->source($moniker);
       my $local_class = $self->{schema} . '::' . $moniker;
       my $local_table = $local_obj->from;
       foreach my $rel (@$rels) {
          my $local_cols = $rel->{local_columns};
          my $remote_moniker = $rel->{remote_source};
          my $remote_obj = $self->{schema}->source($remote_moniker);
          my $remote_class = $self->{schema} . '::' . $remote_moniker; # XXX
          my $remote_table = $remote_obj->from;
          my $remote_cols = $rel->{remote_columns};
          if( !defined $remote_cols) {
              $remote_cols = [ $remote_obj->primary_columns ];
          }
          my %cond;
          while(@$local_cols) {
              my $lcol = shift @$local_cols;
              my $rcol = shift @$remote_cols;
              $cond{$rcol} = $lcol;
          }
          my $code = $self->_make_rel_codes($local_table, $local_class, $moniker,
                                            $remote_table, $remote_class, $remote_moniker,
                                            \%cond);
          foreach my $src_class (keys %$code) {
              push(@{$all_code->{$src_class}}, @{$code->{$src_class}});
          }
       }
    }

    return $all_code;
}

sub setup_rels {
    my ($self, $debug) = @_;

    my $codes = $self->generate_code;
    foreach my $src_class (sort keys %$codes) {
        foreach my $code (@{$codes->{$src_class}}) {
            my $to_eval = $src_class . '->' . $code;
            warn "$to_eval\n" if $debug;
            eval $to_eval;
            die $@ if $@;
        }
    }
}

# not a class method, just a helper for cond_rel XXX
sub _stringify_hash {
    my $href = shift;

    return '{ ' .
           join(q{, }, map("'$_' => '$href->{$_}'", keys %$href))
           . ' }';
}

# Set up a pair of relationships
sub _make_rel_codes {
    my ( $self, $table, $table_class, $table_moniker, $other_table, $other_class, $other_moniker, $cond ) = @_;

    my $table_relname = $self->_inflect_relname(lc $table);
    my $other_relname = lc $other_table;

    # for single-column case, set the relname to the column name,
    # to make filter accessors work
    if(scalar keys %$cond == 1) {
        my ($col) = keys %$cond;
        $other_relname = $cond->{$col};
    }

    my $rev_cond = { reverse %$cond };

    for (keys %$rev_cond) {
        $rev_cond->{"foreign.$_"} = "self.".$rev_cond->{$_};
        delete $rev_cond->{$_};
    }

    my $cond_printable = _stringify_hash($cond);
    my $rev_cond_printable = _stringify_hash($rev_cond);

    my %output_codes;

    push(@{$output_codes{$table_class}},
        qq{belongs_to( '$other_relname' => '$other_moniker'}
      . qq{, $cond_printable);});

    push(@{$output_codes{$other_class}},
        qq{has_many( '$table_relname' => '$table_moniker'}
      . qq{, $rev_cond_printable);});

    return \%output_codes;
}

1;
