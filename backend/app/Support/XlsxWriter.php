<?php

namespace App\Support;

use RuntimeException;
use ZipArchive;

/**
 * Minimal single-sheet .xlsx writer (header row, text/number cells, formula
 * hyperlinks, embedded pictures). It only needs ext-zip - pictures are passed in
 * as already-encoded JPEG/PNG bytes, so no spreadsheet library or GD is required
 * here (GD is only used by callers to make the thumbnails).
 */
class XlsxWriter
{
    private const EMU_PER_PX = 9525;

    /** @var array<int, array<int, mixed>> */
    private array $rows = [];

    /** @var array<int, float> column index (0-based) => width in characters */
    private array $columnWidths = [];

    /** @var array<int, float> 1-based row number => height in points */
    private array $rowHeights = [];

    /** @var array<int, array{row: int, col: int, bytes: string, ext: string, width: int, height: int}> */
    private array $pictures = [];

    public function __construct(private readonly string $sheetName = 'Sheet1')
    {
    }

    /** @param array<int, mixed> $cells string|int|float|null, or ['link' => url, 'text' => label] */
    public function addRow(array $cells, ?float $heightPoints = null): int
    {
        $this->rows[] = $cells;
        $rowNumber = count($this->rows);
        if ($heightPoints !== null) {
            $this->rowHeights[$rowNumber] = $heightPoints;
        }

        return $rowNumber;
    }

    public function setColumnWidth(int $column, float $characters): void
    {
        $this->columnWidths[$column] = $characters;
    }

    /** Place a picture at the top-left of a cell (row is 1-based, column 0-based). */
    public function addPicture(int $row, int $column, string $bytes, string $ext, int $widthPx, int $heightPx): void
    {
        $this->pictures[] = [
            'row' => $row, 'col' => $column, 'bytes' => $bytes, 'ext' => $ext === 'png' ? 'png' : 'jpeg',
            'width' => $widthPx, 'height' => $heightPx,
        ];
    }

    public function save(string $path): void
    {
        $zip = new ZipArchive;
        if ($zip->open($path, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
            throw new RuntimeException('Could not create the Excel file.');
        }

        $hasPictures = $this->pictures !== [];

        $zip->addFromString('[Content_Types].xml', $this->contentTypes($hasPictures));
        $zip->addFromString('_rels/.rels', $this->rootRels());
        $zip->addFromString('xl/workbook.xml', $this->workbook());
        $zip->addFromString('xl/_rels/workbook.xml.rels', $this->workbookRels());
        $zip->addFromString('xl/styles.xml', $this->styles());
        $zip->addFromString('xl/worksheets/sheet1.xml', $this->sheet($hasPictures));

        if ($hasPictures) {
            $zip->addFromString('xl/worksheets/_rels/sheet1.xml.rels',
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'
                .'</Relationships>');
            $zip->addFromString('xl/drawings/drawing1.xml', $this->drawing());

            $rels = '';
            foreach ($this->pictures as $i => $picture) {
                $n = $i + 1;
                $ext = $picture['ext'] === 'png' ? 'png' : 'jpeg';
                $zip->addFromString("xl/media/image{$n}.{$ext}", $picture['bytes']);
                $rels .= '<Relationship Id="rId'.$n.'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image'.$n.'.'.$ext.'"/>';
            }
            $zip->addFromString('xl/drawings/_rels/drawing1.xml.rels',
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'.$rels.'</Relationships>');
        }

        if (! $zip->close()) {
            throw new RuntimeException('Could not write the Excel file.');
        }
    }

    // ---------------------------------------------------------------- parts

    private function contentTypes(bool $hasPictures): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            .'<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            .'<Default Extension="xml" ContentType="application/xml"/>'
            .($hasPictures ? '<Default Extension="jpeg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/>' : '')
            .'<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            .'<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            .'<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            .($hasPictures ? '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>' : '')
            .'</Types>';
    }

    private function rootRels(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            .'</Relationships>';
    }

    private function workbook(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            .'<sheets><sheet name="'.$this->xml($this->sheetName).'" sheetId="1" r:id="rId1"/></sheets>'
            .'</workbook>';
    }

    private function workbookRels(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            .'<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            .'</Relationships>';
    }

    // cellXfs: 0 default, 1 header (white bold on green, centred), 2 wrapped top-aligned,
    // 3 hyperlink-looking text (blue underline, centred vertically).
    private function styles(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            .'<fonts count="3">'
            .'<font><sz val="10"/><name val="Calibri"/></font>'
            .'<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
            .'<font><u/><sz val="10"/><color rgb="FF1565C0"/><name val="Calibri"/></font>'
            .'</fonts>'
            .'<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
            .'<fill><patternFill patternType="solid"><fgColor rgb="FF1B6B43"/><bgColor indexed="64"/></patternFill></fill></fills>'
            .'<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
            .'<border><left style="thin"><color rgb="FFD0D5CC"/></left><right style="thin"><color rgb="FFD0D5CC"/></right>'
            .'<top style="thin"><color rgb="FFD0D5CC"/></top><bottom style="thin"><color rgb="FFD0D5CC"/></bottom><diagonal/></border></borders>'
            .'<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            .'<cellXfs count="4">'
            .'<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'
            .'<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
            .'<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
            .'<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
            .'</cellXfs>'
            .'<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
            .'</styleSheet>';
    }

    private function sheet(bool $hasDrawing): string
    {
        $lastColumn = 0;
        foreach ($this->rows as $row) {
            $lastColumn = max($lastColumn, count($row));
        }

        $xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            .'<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
            .'<sheetFormatPr defaultRowHeight="15"/>';

        if ($this->columnWidths) {
            $xml .= '<cols>';
            ksort($this->columnWidths);
            foreach ($this->columnWidths as $col => $width) {
                $n = $col + 1;
                $xml .= '<col min="'.$n.'" max="'.$n.'" width="'.$width.'" customWidth="1"/>';
            }
            $xml .= '</cols>';
        }

        $xml .= '<sheetData>';
        foreach ($this->rows as $index => $cells) {
            $rowNumber = $index + 1;
            $height = $this->rowHeights[$rowNumber] ?? null;
            $xml .= '<row r="'.$rowNumber.'"'.($height ? ' ht="'.$height.'" customHeight="1"' : '').'>';
            foreach ($cells as $col => $value) {
                $xml .= $this->cell($rowNumber, $col, $value, $rowNumber === 1);
            }
            $xml .= '</row>';
        }
        $xml .= '</sheetData>';

        if ($lastColumn > 0 && count($this->rows) > 1) {
            $xml .= '<autoFilter ref="A1:'.$this->columnName($lastColumn - 1).count($this->rows).'"/>';
        }
        $xml .= '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>';
        if ($hasDrawing) {
            $xml .= '<drawing r:id="rId1"/>';
        }

        return $xml.'</worksheet>';
    }

    private function cell(int $row, int $col, mixed $value, bool $header): string
    {
        $ref = $this->columnName($col).$row;

        if ($value === null || $value === '') {
            return '<c r="'.$ref.'" s="'.($header ? 1 : 0).'"/>';
        }

        if ($header) {
            return '<c r="'.$ref.'" s="1" t="inlineStr"><is><t xml:space="preserve">'.$this->xml((string) $value).'</t></is></c>';
        }

        if (is_array($value) && isset($value['link'])) {
            $formula = 'HYPERLINK("'.str_replace('"', '""', $value['link']).'","'.str_replace('"', '""', (string) ($value['text'] ?? 'Open')).'")';

            return '<c r="'.$ref.'" s="3" t="str"><f>'.$this->xml($formula).'</f><v>'.$this->xml((string) ($value['text'] ?? 'Open')).'</v></c>';
        }

        if (is_int($value) || is_float($value)) {
            return '<c r="'.$ref.'" s="0"><v>'.$value.'</v></c>';
        }

        return '<c r="'.$ref.'" s="2" t="inlineStr"><is><t xml:space="preserve">'.$this->xml((string) $value).'</t></is></c>';
    }

    private function drawing(): string
    {
        $xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
            .'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">';

        foreach ($this->pictures as $i => $picture) {
            $n = $i + 1;
            $cx = $picture['width'] * self::EMU_PER_PX;
            $cy = $picture['height'] * self::EMU_PER_PX;
            $xml .= '<xdr:oneCellAnchor>'
                .'<xdr:from><xdr:col>'.$picture['col'].'</xdr:col><xdr:colOff>'.(3 * self::EMU_PER_PX).'</xdr:colOff>'
                .'<xdr:row>'.($picture['row'] - 1).'</xdr:row><xdr:rowOff>'.(3 * self::EMU_PER_PX).'</xdr:rowOff></xdr:from>'
                .'<xdr:ext cx="'.$cx.'" cy="'.$cy.'"/>'
                .'<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="'.($n + 1).'" name="Photo '.$n.'"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
                .'<xdr:blipFill><a:blip r:embed="rId'.$n.'"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
                .'<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="'.$cx.'" cy="'.$cy.'"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
                .'<xdr:clientData/></xdr:oneCellAnchor>';
        }

        return $xml.'</xdr:wsDr>';
    }

    // ---------------------------------------------------------------- helpers

    /** 0 -> A, 25 -> Z, 26 -> AA ... */
    private function columnName(int $index): string
    {
        $name = '';
        for ($n = $index + 1; $n > 0; $n = intdiv($n - 1, 26)) {
            $name = chr(65 + ($n - 1) % 26).$name;
        }

        return $name;
    }

    /** Escape for XML text/attributes and drop characters XML 1.0 forbids. */
    private function xml(string $value): string
    {
        $value = preg_replace('/[^\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/u', '', $value) ?? '';

        return htmlspecialchars($value, ENT_XML1 | ENT_QUOTES, 'UTF-8');
    }
}
