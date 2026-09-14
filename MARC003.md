# Source-specific MARC 003 transforms

Koha Z39.50/SRU targets can apply one or more XSLT files to retrieved MARC
records before those records are put into Koha's import reservoir. This image
uses that hook to fill a missing MARC 21 `003` with the identifier for the
source which supplied the `001` control number.

The generated transform is deliberately conservative:

- an existing non-empty `003` is preserved;
- an existing empty `003` is filled;
- a missing `003` is inserted immediately after `001`;
- no `003` is added if the record has no `001`.

The files are generated at container startup from
`templates/add-marc003.xsl.in`. Koha still requires a separate XSLT filename on
each target, so the generated filenames are:

```
GeneratedAdd003-<identifier>.xsl
```

## Built-in identifiers

The default list is:

```
CaAENA,DE-604,StEdNL,WlAbNL,UkBU,UkOxU,DLC
```

For the targets used by this image/application, configure Koha's
**XSLT File(s) for transforming results** field as follows:

| Target | MARC 003 identifier | XSLT filename |
| --- | --- | --- |
| Northern Alberta Institute of Technology (NAIT) | `CaAENA` | `GeneratedAdd003-CaAENA.xsl` |
| BVB Bayern | `DE-604` | `GeneratedAdd003-DE-604.xsl` |
| National Library of Scotland | `StEdNL` | `GeneratedAdd003-StEdNL.xsl` |
| National Library of Wales | `WlAbNL` | `GeneratedAdd003-WlAbNL.xsl` |
| University of Birmingham | `UkBU` | `GeneratedAdd003-UkBU.xsl` |
| Oxford Bodleian Libraries | `UkOxU` | `GeneratedAdd003-UkOxU.xsl` |
| Library of Congress (LCDB) | `DLC` | `GeneratedAdd003-DLC.xsl` |
| Library of Congress SRU (LCDB) | `DLC` | `GeneratedAdd003-DLC.xsl` |
| Library of Congress Names (NAF) | `DLC` | `GeneratedAdd003-DLC.xsl` |
| Library of Congress Subjects (SAF) | `DLC` | `GeneratedAdd003-DLC.xsl` |

`CaAENA` follows the Canadian MARC convention (`Ca` plus the Library and
Archives Canada library symbol `AENA` for NAIT/McNally Library).

`DE-604` is the German ISIL for Bibliotheksverbund Bayern. MARC 21 permits ISIL
identifiers in the organization-code fields as well as traditional MARC
organization codes.

The JULAC Alma network target is intentionally not in the default list. Its
network records use `852JULAC_NETWORK` identifiers, but no authoritative
MARC/ISIL identifier for the network itself has been identified. Add one with
the append variable below if an authoritative identifier becomes available.

The Bibliotheque nationale de France target is also intentionally excluded: it
is configured as UNIMARC, so this MARC 21 `003` transform is not applicable.

Reference sources:

- British Library, *MARC codes for organizations in the UK and its
  dependencies*: https://www.bl.uk/more/collection-metadata-services/marc-codes-directory.pdf
- Library of Congress, MARC Code List for Organizations:
  https://www.loc.gov/marc/organizations/
- Deutsche ISIL-Agentur, `DE-604` Bibliotheksverbund Bayern:
  https://isil.staatsbibliothek-berlin.de/isil/DE-604
- Library and Archives Canada, *Symbols and Interlibrary Loan Policies in
  Canada* (library symbol `AENA`).

## Runtime configuration

`KOHA_MARC003_XSLT_CODES` replaces the complete built-in list. An explicitly
empty value disables the built-in transforms:

```yaml
environment:
  KOHA_MARC003_XSLT_CODES: "UkOxU,DLC"
```

or:

```yaml
environment:
  KOHA_MARC003_XSLT_CODES: ""
```

`KOHA_MARC003_XSLT_CODES_APPEND` adds identifiers without replacing the image
defaults:

```yaml
environment:
  KOHA_MARC003_XSLT_CODES_APPEND: "UkFoo,UkBar"
```

Whitespace around comma-separated entries is ignored and duplicate identifiers
are removed. Identifiers may contain ASCII letters, digits and `-`; invalid
values abort startup before the previous generated set is replaced.

At startup the container logs each generated filename, for example:

```
*** Generated MARC 003 Z39.50/SRU transforms:
***   UkOxU -> GeneratedAdd003-UkOxU.xsl
***   DLC -> GeneratedAdd003-DLC.xsl
```

After adding a new identifier, select the matching generated filename in
Koha under **Administration -> Z39.50/SRU servers -> <target> -> XSLT File(s)
for transforming results**.
