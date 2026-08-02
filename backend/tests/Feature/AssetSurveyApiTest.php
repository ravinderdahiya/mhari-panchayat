<?php

namespace Tests\Feature;

use App\Models\AssetType;
use App\Models\Department;
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
}
