<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\LocationController;
use App\Models\AssetType;
use App\Models\Block;
use App\Models\Department;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AssetSurveyApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_surveyor_can_save_asset_survey_and_admin_can_see_identity_and_asset(): void
    {
        Storage::fake('public');
        $department = Department::create(['name' => 'Animal Husbandry', 'code' => 'AH']);
        $assetType = AssetType::create(['name' => 'Veterinary Hospital', 'icon_key' => 'local_hospital']);
        $assetType->departments()->attach($department);

        $surveyor = User::factory()->create([
            'role' => 'engineer',
            'department_id' => $department->id,
            'employee_id' => 'SUR-HSR-0001',
        ]);
        $surveyor->departments()->attach($department);

        $response = $this->actingAs($surveyor, 'sanctum')->post('/api/surveys', [
            'departmentId' => $department->id,
            'assetTypeId' => $assetType->id,
            'assetName' => 'Government Veterinary Hospital Satrod',
            'district' => 'Hisar',
            'panchayat' => 'Hisar I Block',
            'village' => 'Satrod Kalan',
            'latitude' => 29.097869,
            'longitude' => 75.800000,
            'condition' => 'GOOD',
            'description' => 'Field survey test',
            'surveyDate' => now()->toISOString(),
            'photos' => [UploadedFile::fake()->image('survey.jpg', 800, 600)],
        ]);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('survey.surveyor.employeeId', 'SUR-HSR-0001')
            ->assertJsonPath('survey.departmentName', 'Animal Husbandry')
            ->assertJsonPath('survey.assetTypeName', 'Veterinary Hospital')
            ->assertJsonPath('survey.assetName', 'Government Veterinary Hospital Satrod');

        $this->assertDatabaseHas('asset_surveys', [
            'surveyor_id' => $surveyor->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
            'village' => 'Satrod Kalan',
        ]);

        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin, 'sanctum')->getJson('/api/surveys')
            ->assertOk()
            ->assertJsonPath('surveys.0.surveyedByName', $surveyor->name)
            ->assertJsonPath('surveys.0.assetTypeName', 'Veterinary Hospital');
    }

    public function test_cplo_sees_only_assigned_departments_and_can_save_survey(): void
    {
        Storage::fake('public');
        [$pr, $assetType, $cplo, $panchayat] = $this->makeCploWithPanchayat();

        $this->actingAs($cplo, 'sanctum')->getJson('/api/survey-departments')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonCount(1, 'departments')
            ->assertJsonPath('departments.0.code', 'PR');

        $this->mock(LocationController::class, function ($mock) use ($panchayat) {
            $mock->shouldReceive('lookup')->andReturn([
                'panchayatId' => $panchayat->id,
                'panchayat' => $panchayat->name,
            ]);
        });

        $this->actingAs($cplo, 'sanctum')->post('/api/surveys', [
            'departmentId' => $pr->id,
            'assetTypeId' => $assetType->id,
            'assetName' => 'Bir Hisar Chaupal',
            'district' => 'Hisar',
            'panchayat' => 'Bir Hisar',
            'village' => 'Bir Hisar',
            'latitude' => 29.1492,
            'longitude' => 75.7217,
            'condition' => 'GOOD',
            'description' => 'CPLO field survey',
            'surveyDate' => now()->toISOString(),
            'photos' => [UploadedFile::fake()->image('cplo.jpg', 800, 600)],
        ])->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('survey.surveyor.role', 'cplo');

        $this->assertDatabaseHas('asset_surveys', [
            'surveyor_id' => $cplo->id,
            'department_id' => $pr->id,
            'village' => 'Bir Hisar',
        ]);
    }

    public function test_cplo_cannot_save_survey_outside_assigned_panchayat(): void
    {
        Storage::fake('public');
        [$pr, $assetType, $cplo] = $this->makeCploWithPanchayat();

        $this->mock(LocationController::class, function ($mock) {
            $mock->shouldReceive('lookup')->andReturn([
                'panchayatId' => 99999,
                'panchayat' => 'Other Panchayat',
            ]);
        });

        $this->actingAs($cplo, 'sanctum')->post('/api/surveys', [
            'departmentId' => $pr->id,
            'assetTypeId' => $assetType->id,
            'assetName' => 'Outside Area Asset',
            'district' => 'Hisar',
            'panchayat' => 'Bir Hisar',
            'village' => 'Other Village',
            'latitude' => 28.6139,
            'longitude' => 77.2090,
            'condition' => 'GOOD',
            'description' => 'Should be blocked',
            'surveyDate' => now()->toISOString(),
            'photos' => [UploadedFile::fake()->image('outside.jpg', 800, 600)],
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['panchayat']);

        $this->assertDatabaseMissing('asset_surveys', [
            'surveyor_id' => $cplo->id,
            'asset_name' => 'Outside Area Asset',
        ]);
    }

    public function test_cplo_without_assigned_panchayat_cannot_save_survey(): void
    {
        Storage::fake('public');
        $pr = Department::create(['name' => 'Panchayati Raj', 'code' => 'PR', 'is_active' => true]);
        $assetType = AssetType::create(['name' => 'Community Centre', 'icon_key' => 'home']);
        $assetType->departments()->attach($pr);

        $cplo = User::factory()->create([
            'role' => 'cplo',
            'department_id' => $pr->id,
        ]);
        $cplo->departments()->attach($pr);

        $this->actingAs($cplo, 'sanctum')->post('/api/surveys', [
            'departmentId' => $pr->id,
            'assetTypeId' => $assetType->id,
            'assetName' => 'No Assignment Asset',
            'district' => 'Hisar',
            'panchayat' => 'Bir Hisar',
            'village' => 'Bir Hisar',
            'latitude' => 29.1492,
            'longitude' => 75.7217,
            'condition' => 'GOOD',
            'description' => 'Should be blocked',
            'surveyDate' => now()->toISOString(),
            'photos' => [UploadedFile::fake()->image('none.jpg', 800, 600)],
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['panchayat']);
    }

    /** @return array{0: Department, 1: AssetType, 2: User, 3: Panchayat} */
    private function makeCploWithPanchayat(): array
    {
        $pr = Department::create(['name' => 'Panchayati Raj', 'code' => 'PR', 'is_active' => true]);
        $assetType = AssetType::create(['name' => 'Community Centre', 'icon_key' => 'home']);
        $assetType->departments()->attach($pr);

        $state = State::create(['name' => 'Haryana', 'code' => 'HR']);
        $district = District::create(['name' => 'Hisar', 'code' => 'HSR', 'state_id' => $state->id]);
        $block = Block::create(['name' => 'Hisar I', 'code' => 'HIS1', 'district_id' => $district->id]);
        $panchayat = Panchayat::create(['name' => 'Bir Hisar', 'code' => 'BIRH', 'block_id' => $block->id]);

        $cplo = User::factory()->create([
            'role' => 'cplo',
            'department_id' => $pr->id,
            'district_id' => $district->id,
            'block_id' => $block->id,
            'panchayat_id' => $panchayat->id,
        ]);
        $cplo->departments()->attach($pr);

        return [$pr, $assetType, $cplo, $panchayat];
    }
}
