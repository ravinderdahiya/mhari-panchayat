<?php

namespace Tests\Feature;

use App\Models\Block;
use App\Models\AssetType;
use App\Models\ComplaintCategory;
use App\Models\ComplaintPriority;
use App\Models\District;
use App\Models\Department;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\Tehsil;
use App\Models\User;
use App\Models\Village;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ComplaintSubmissionApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_citizen_gets_filtered_options_and_submits_a_location_based_complaint(): void
    {
        Storage::fake('public');
        $this->seed(PermissionSeeder::class);

        $state = State::create(['name' => 'Haryana', 'code' => 'HR']);
        $district = District::create(['name' => 'Hisar', 'code' => 'HSR', 'state_id' => $state->id]);
        $otherDistrict = District::create(['name' => 'Rohtak', 'code' => 'RTK', 'state_id' => $state->id]);
        $tehsil = Tehsil::create(['name' => 'Hisar', 'code' => 'HIS', 'district_id' => $district->id]);

        $block = Block::create(['name' => 'Hisar I', 'code' => 'HIS1', 'district_id' => $district->id]);
        $panchayat = Panchayat::create(['name' => 'Satrod', 'code' => 'SAT', 'block_id' => $block->id]);
        $village = Village::create(['name' => 'Satrod Kalan', 'code' => 'SATK', 'panchayat_id' => $panchayat->id, 'tehsil_id' => $tehsil->id]);

        $otherBlock = Block::create(['name' => 'Rohtak', 'code' => 'RTK1', 'district_id' => $otherDistrict->id]);
        $otherPanchayat = Panchayat::create(['name' => 'Bohar', 'code' => 'BOH', 'block_id' => $otherBlock->id]);
        Village::create(['name' => 'Bohar', 'code' => 'BOHV', 'panchayat_id' => $otherPanchayat->id]);

        $category = ComplaintCategory::create(['name' => 'Road', 'code' => 'ROAD', 'sort_order' => 1]);
        $priority = ComplaintPriority::create(['name' => 'Medium', 'level' => 2]);
        $department = Department::create(['name' => 'School Education Department', 'code' => 'SED']);
        $assetType = AssetType::create(['name' => 'Govt. Primary School', 'icon_key' => 'school']);
        $assetType->departments()->attach($department);
        $citizen = User::factory()->create(['role' => 'citizen', 'district_id' => null]);

        $this->actingAs($citizen, 'sanctum')
            ->getJson("/api/complaints/form-options?district_id={$district->id}&tehsil_id={$tehsil->id}")
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonCount(1, 'tehsils')
            ->assertJsonCount(1, 'villages')
            ->assertJsonPath('villages.0.name', 'Satrod Kalan')
            ->assertJsonPath('villages.0.panchayatName', 'Satrod');

        $response = $this->actingAs($citizen, 'sanctum')->post('/api/complaints', [
            'district_id' => $district->id,
            'tehsil_id' => $tehsil->id,
            'village_id' => $village->id,
            'category_id' => $category->id,
            'priority_id' => $priority->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
            'description' => 'The village road has a large unsafe pothole.',
            'lat' => 29.1492,
            'long' => 75.7217,
            'photo' => UploadedFile::fake()->create('pothole.jpg', 100, 'image/jpeg'),
        ]);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('complaint.status', 'Pending')
            ->assertJsonPath('complaint.village', 'Satrod Kalan')
            ->assertJsonPath('complaint.panchayat', 'Satrod')
            ->assertJsonPath('complaint.district.name', 'Hisar')
            ->assertJsonPath('complaint.tehsil.name', 'Hisar')
            ->assertJsonPath('complaint.category.name', 'Road')
            ->assertJsonPath('complaint.priority.name', 'Medium');
        $response->assertJsonPath('complaint.department.name', 'School Education Department')
            ->assertJsonPath('complaint.asset_type.name', 'Govt. Primary School')
            ->assertJsonCount(1, 'complaint.issue_photo_urls');

        $multiPhoto = $this->actingAs($citizen, 'sanctum')->post('/api/complaints', [
            'district_id' => $district->id,
            'tehsil_id' => $tehsil->id,
            'village_id' => $village->id,
            'category_id' => $category->id,
            'priority_id' => $priority->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
            'description' => 'Multiple photos of the same pothole from different angles.',
            'lat' => 29.1492,
            'long' => 75.7217,
            'photos' => [
                UploadedFile::fake()->create('pothole1.jpg', 100, 'image/jpeg'),
                UploadedFile::fake()->create('pothole2.jpg', 100, 'image/jpeg'),
                UploadedFile::fake()->create('pothole3.jpg', 100, 'image/jpeg'),
            ],
        ]);

        $multiPhoto->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonCount(3, 'complaint.issue_photo_urls');
        $this->assertNotNull($multiPhoto->json('complaint.before_photo_url'));
        $this->assertSame(
            $multiPhoto->json('complaint.before_photo_url'),
            $multiPhoto->json('complaint.issue_photo_urls.0'),
        );

        $this->assertDatabaseHas('complaints', [
            'user_id' => $citizen->id,
            'district_id' => $district->id,
            'tehsil_id' => $tehsil->id,
            'village_id' => $village->id,
            'panchayat_id' => $panchayat->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
            'status' => 'Pending',
        ]);
        $this->assertDatabaseHas('complaint_timeline_events', [
            'status' => 'Pending',
            'title' => 'Complaint Filed',
        ]);
    }
}
