<?php

namespace Tests\Unit;

use App\Support\XlsxWriter;
use PHPUnit\Framework\TestCase;
use ZipArchive;

class XlsxWriterTest extends TestCase
{
    private string $path;

    protected function setUp(): void
    {
        $this->path = sys_get_temp_dir().DIRECTORY_SEPARATOR.'xlsx_writer_'.uniqid().'.xlsx';
    }

    protected function tearDown(): void
    {
        @unlink($this->path);
    }

    private function entry(string $name): string
    {
        $zip = new ZipArchive;
        $this->assertTrue($zip->open($this->path) === true);
        $content = $zip->getFromName($name);
        $zip->close();
        $this->assertNotFalse($content, "missing {$name}");

        return $content;
    }

    public function test_writes_a_well_formed_workbook_with_header_text_numbers_and_links(): void
    {
        $sheet = new XlsxWriter('Asset Surveys');
        $sheet->addRow(['No', 'Name', 'Lat']);
        $sheet->addRow([1, 'रामलाल <&> "Co"', 29.5]);
        $sheet->addRow([2, ['link' => 'http://x.test/a.jpg', 'text' => 'Photo 1'], null]);
        $sheet->setColumnWidth(1, 30);
        $sheet->save($this->path);

        foreach (['[Content_Types].xml', 'xl/workbook.xml', 'xl/styles.xml', 'xl/worksheets/sheet1.xml'] as $part) {
            $this->assertNotFalse(simplexml_load_string($this->entry($part)), "{$part} is not well-formed XML");
        }

        $sheetXml = $this->entry('xl/worksheets/sheet1.xml');
        $this->assertStringContainsString('रामलाल &lt;&amp;&gt; &quot;Co&quot;', $sheetXml);
        $this->assertStringContainsString('<c r="C2" s="0"><v>29.5</v></c>', $sheetXml);
        $this->assertStringContainsString('HYPERLINK(&quot;http://x.test/a.jpg&quot;', $sheetXml);
        $this->assertStringContainsString('<autoFilter ref="A1:C3"/>', $sheetXml);
        $this->assertStringNotContainsString('<drawing', $sheetXml);
    }

    public function test_embeds_pictures_anchored_to_their_cell(): void
    {
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

        $sheet = new XlsxWriter;
        $sheet->addRow(['Photo']);
        $row = $sheet->addRow([null], 60);
        $sheet->addPicture($row, 0, $png, 'png', 40, 30);
        $sheet->save($this->path);

        $this->assertSame($png, $this->entry('xl/media/image1.png'));
        $this->assertStringContainsString('<drawing r:id="rId1"/>', $this->entry('xl/worksheets/sheet1.xml'));

        $drawing = $this->entry('xl/drawings/drawing1.xml');
        $this->assertNotFalse(simplexml_load_string($drawing));
        $this->assertStringContainsString('<xdr:row>1</xdr:row>', $drawing); // row 2, zero-based
        $this->assertStringContainsString('cx="'.(40 * 9525).'"', $drawing);
        $this->assertStringContainsString('ContentType="image/png"', $this->entry('[Content_Types].xml'));
    }

    public function test_strips_characters_xml_cannot_hold(): void
    {
        $sheet = new XlsxWriter;
        $sheet->addRow(['H']);
        $sheet->addRow(["bad\x00\x0Bchar"]);
        $sheet->save($this->path);

        $xml = $this->entry('xl/worksheets/sheet1.xml');
        $this->assertNotFalse(simplexml_load_string($xml));
        $this->assertStringContainsString('>badchar<', $xml);
    }
}
