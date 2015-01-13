#!/usr/bin/perl
use strict;
use warnings;

use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use LWP::Simple qw(get);
use PICA::Record;

# Datenbank (unAPI-Prefix)
my $db = param('db') || 'gvk';
$db = 'gvk' unless $db =~ /^[0-9a-z-]+$/;

my $dburl = "http://gso.gbv.de/DB=$db"; # TODO: holen via unAPI
my $limit = 20;
my $debug = param('debug');

# PPNs auslesen und alles außer PPN entfernen
my @ppns = 
    grep { $_ }
    map { /^\s*["']?($db:ppn:)?([0-9]+[0-9X])/i ? $2 : '' } 
    split("\n", param('ppn') || "");
@ppns = @ppns[0..($limit-1)] if @ppns > $limit;
param('ppn', join("\n", @ppns ));

# ILN ermitteln (z.B. 69 für Greifswald)
my $iln = param('iln') || "";
$iln =~ s/^\s+|\s+$//g;
my @ilns = grep { $_ } split /\s*,\s*/, $iln;
param('iln', join(", ",@ilns));

# CSV-Modus
my $csvmode = param('csv');

# Ausnahmen
my @exceptions = map { parse_exception($_) } grep { $_ }
                 split("\n", param('exceptions') || "");
param('exceptions',
    join("\n",
      map { ref($_) eq 'HASH'
          ? $_->{field} . " " . $_->{op} . " " . $_->{value}
          : "SYNTAXFEHLER: $_"
        } @exceptions
    ));

sub parse_exception {
    my $line = shift;
    chomp $line;
    $line =~ s/^\s*[A-Z]+:\s*//;
    if ($line =~ /^(2[0-9][0-9][A-Z@]\$[0-9a-zA-Z]+)\s*([=~])\s*(.*)$/) {
        my ($field, $op, $value, $regexp) = ($1, $2, $3);
        if ($op eq '~') {
            $regexp = eval { qr/$value/ };
            if ($@) {
                my $error = $@;
                $error =~ s/at \/.*$//;
                $error =~ s/\n//;
                return "$error: $line";
            }
        }
        return { field => $field, op => $op, value => $value, regexp => $regexp };
    } else {
        return $line;
    }
}


my %result;
my %skipped;
my %holders;
my %librarynames;
my %ilns = map { $_ => 1 } @ilns;

sub itemcount {
    my $item = shift;
    my $count = $item->sf('209A(/..)?$e');
    return (defined $count && $count > 1) ? $count : 1;
}

my $ee;

sub itemException {
    my $item = shift;
    return 0 unless @exceptions;

    foreach my $e (@exceptions) {
        my $field = $e->{field};
        $field =~ s/\$/\(\/\.\.\)\?\$/; # any occurrence
        my $value = $item->subfield($field);

        $ee .= "$field = $value" if $debug;

        if ($e->{op} eq '=') {
            $ee .= " = \n" if $debug;
            return 1 if $value eq $e->{value};
        } elsif ($e->{op} eq '~') {
            $ee .= " ~ " . ( $value =~ $e->{regexp} ? 1 : 0 ) . "\n";
            return 1 if $value =~ $e->{regexp};
        }
    }

    return 0;
}
# TODO: mehrere ILNs komma-seperiert erlauben

if (@ppns) {
    foreach my $ppn (@ppns) {
        my $record;

        my $id = "$db:ppn:$ppn";
        my $url = "http://unapi.gbv.de/?format=pp&id=$id";
        $record = eval { PICA::Record->new( get($url) ); };
        next unless $record;

        my @holdings = $record->holdings(  ); # TODO: multiple $ilns
        foreach my $holdings ( @holdings  ) {
            next unless not @ilns or defined $ilns{ $holdings->iln };
            my $count = 0;
            if ($holdings) {
                my @allitems = $holdings->items;
                my @items = grep { not itemException($_) } @allitems;
                #if (@exceptions) {
                    $skipped{$ppn} += (scalar @allitems) - (scalar @items);
                #}
                map { $count += itemcount($_) } @items;

                if ($iln and not $librarynames{$iln}) {
                    $librarynames{$iln} = $holdings->sf('101@$d');
                    utf8::encode($librarynames{$iln});
                }
                push @{$holders{$ppn}}, $holdings->iln if $count;
            }
            $result{$ppn} += $count;
        }
    }
}

my %hcount;
%holders = map { 
    my $ppn = $_;
    my $v = $holders{$ppn};
    if ( ref($v) eq 'ARRAY' ) {
        $hcount{$ppn} = scalar @{$v};
        $v = join(",", @{$v});
    } else {
        $v = "";
        $hcount{$ppn} = 0;
    }
    ($ppn => $v);
} keys %holders;

# CSV-Ausgabe
if ( $csvmode ) {
    print header(
        -type => "text/csv; charset=UTF-8",
        -attachment => "itemcount.csv",
    );

    print "PPN;items;exception;libraries;iln\n";
    foreach my $ppn (@ppns) {
        no warnings;
        my $line = join(";", $ppn, $result{$ppn}, $skipped{$ppn}, $hcount{$ppn}, $holders{$ppn});
#        $line .= ";" . $skipped{$ppn} if defined $skipped{$ppn};
        print "$line\n";
    }
    exit;
}


# HTML-Ausgabe
print header( "text/html; charset=UTF-8" );
print <<HTML;
<html xmlns='http://www.w3.org/1999/xhtml'>
<head>
<meta content='text/html; charset=UTF-8' http-equiv='Content-Type'/>
<title>GBV-Exemplarzähler</title>
<style>
    body { font-family: sans-serif; }
    label { font-weight: bold; }
    td { padding-right: 2em; vertical-align: top; }
    th { text-align: left; vertical-align: top; }
    a { text-decoration: none; }
    a:hover { text-decoration: underline }
    a.pplink { font-weight: bold; text-decoration: underline; }
    .result { border: 1px solid #666; padding: 4px; }
</style>
</head><body>
<h1>GBV-Exemplarzähler</h1>
<p>Dieses Formular ermittelt die Anzahl der Exemplare von Titeln einer oder
   aller Bibliotheken im <a href='$dburl'>GBV-Verbundkatalog</a> (GVK) wobei
   Mehrfachexemplare berücksichtigt werden. Die Anzahl der gleichzeitig
   abfragbaren PPNs ist auf $limit begrenzt. Um einzelne Exemplarsätze von
   der Zählung auszunehmen (z.B. Verlust, im Geschäftsgang etc.) können
   Ausnahmen angegeben werden.
</p>
HTML

print start_form;
print input({-type=>'hidden', -name=>'debug', -value=>$debug});

print "<table><tr>";
print th(label("Bibliothek (ILN)<sup>1</sup>")),
      th(label("Datenbank<sup>5</sup>")) . "</tr>";

print td( input({ -name => 'iln', -value => $iln }) .
        " <em>" . join( map { escapeHTML($_) } values %librarynames) . "</em>");
print td( input({ -name => 'db', -value => $db } ) );
print "</tr></table>";
print "<table><tr>";
print th(label("Liste von PPNs<sup>2</sup>")),
      th(label("Ergebnis<sup>3</sup>"),
      th(label("Ausnahmen<sup>4</sup>")));
print "</tr><tr>";
print td(textarea({ -name=>'ppn', -columns => 30, -rows => 20 }));
print "<td>";
if (%result) {
    my @resulthtml;
    my $sum;
    my $skipsum;
    if (@ppns) {
        push @resulthtml, "PPN;items;exception;libraries;iln";
    }
    foreach my $ppn (@ppns) {
        my @line;
        if ( defined $result{$ppn} ) {
            push @line, "<a href='http://ws.gbv.de/daia/gvk/?id=$db:ppn:$ppn' title='Verfügbarkeit'>$ppn</a>"
                      . "<a href='http://unapi.gbv.de/?id=$db:ppn:$ppn&format=pp' class='pplink' title='PICA+ Datensatz'>;</a>"
                      . $result{$ppn};
        } else {
            push @line, $ppn, $result{$ppn};
        }
        push @line, $skipped{$ppn}, $hcount{$ppn}, $holders{$ppn};
        push @resulthtml, join(";", @line);

        $sum += $result{$ppn};
        $skipsum += $skipped{$ppn} if defined $skipped{$ppn};
    }
    print "<div class='result'>" . join("<br>",@resulthtml) . "</div>";
    print "Insgesamt $sum Exemplare von " . scalar(@ppns) . " Titeln. ";
    print "Zusätzlich $skipsum ausgenommene Exemplarsätze." if defined $skipsum;
    print "</div>";
}
print p(
    submit( -name => 'html', -value => 'abfragen als HTML' ),
    submit( -name => 'csv', -value => 'abfragen als CSV' )
);
print "</td><td>";
print textarea({ -name=>'exceptions', -columns => 45, -rows => 5 });
print "<div>";
print <<HTML;
Syntax zeilenweise (ODER-Verknüpfung):<br>
<pre>{Feld}\${Unterfeld} {OP} {Wert}</pre>
<b>Feld</b>: PICA+-Feld z.B. <tt>208\@</tt><br>
<b>Unterfeld</b>: Unterfeld-Indikator(en) z.B. <tt>a</tt><br>
<b>OP</b>: Operator (= / ~)<br>
<b>Wert</b>: Zeichenkette (=) oder regulärer Ausdruck (~)
<br><br>
Beispiel: <tt>208\@\$b ~ ^[ad]</tt> um Sätze mit Selektionsschlüssel a oder d nicht zu zählen.
HTML
print "</div>";
print "</td></tr></table>";

if ($debug) {
    use Data::Dumper;
    print pre(Dumper( \@exceptions ) . $ee);
}

print <<HTML;
</form>
<hr>
<p>Dieses Skript kann auch als Webservice verwendet werden, indem der URL-Parameter 
   <tt>csv=1</tt> gesetzt wird.</p>
<table>
<tr><th colspan='2'>Parameter</th></tr>
<tr><th><sup>1</sup></th><td><tt>iln</tt></td><td>
  Bei Angabe einer oder einer Komma-getrennten Liste von mehreren
  ILN (Internal Library Number, PICA+ Feld <tt>101\@\$a</tt>) wird
  die Zählung auf Exemplare der Bibliotheken mit diesen ILN beschränkt.
</td></tr>
<tr><th><sup>2</sup></th><td><tt>ppn</tt></td><td>
  Die Titel werden zeilenweise durch ihre GBV-PPN angegeben. Die
  PPN besteht aus Ziffern, das letzte Zeichen kann auch ein X sein; optional ist 
  das PPN-Präfix <tt>gvk:ppn:</tt> möglich. Führende Leerzeichen und alles nach der
  PPN wird ignoriert; es können also z.B. auch CSV-Daten übergeben werden, deren erste
  Spalte die PPN enthält.
</td></tr>
<tr><th><sup>3</sup></th><td><tt>csv</tt><br>oder<br><tt>html</tt></td><td>
  Das Ergebnis ist eine CSV-Tabelle mit Semikolon als Trennzeichen deren erste Spalte
  die PPN enthält. Falls ein Titel im GVK gefunden wurde, enthält die zweite Spalte
  die Anzahl der gezählten Exemplare. Falls Ausnahmen angegeben wurden, enthält die
  dritte Spalte die Anzahl der nicht berücksichtigten Exemplardatensätze. Die vierte
  Spalte enthält die Anzahl der Bibliotheken und die fünfte Spalte Komma-getrennt eine
  Liste der ILNs der Bibliotheken mit Exemplarsätzen, sofern diese nicht bei der 
  Zählung ausgenommen wurden.
</td></tr>
<tr><th><sup>4</sup></th><td><tt>exception</tt></td><td>
  Ausnahmen nehmen Exemplarsätze mit bestimmten PICA+-Feldinhalten von der Zählung aus -
  die Zahl der ausgenommenen Sätze (ohne Mehrfachexemplarzählung) erscheint in diesem
  Fall als dritte Ergebnisspalte.
<tr><th><sup>5</sup></th><td><tt>db</tt></td><td>
  Datenbank-Key. Für eine vollständige Liste siehe 
  <a href="http://unapi.gbv.de/about">unAPI-Schnittstelle</a>. 
  Der Standardwert ist 'gvk' für den Gemeinsamen Verbundkatalog.
</tr></table>
</body>
<hr>
<p>Dieses Skript und ähnliche Auswertungen sind möglich mit 
   <a href='http://www.gbv.de/wikis/cls/PICA::Record'>PICA::Record</a>.</p>
</html>
HTML
