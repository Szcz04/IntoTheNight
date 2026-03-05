=== ItemModels Folder ===

Ten folder jest przeznaczony na modele 3D itemów które będą dropowane w świecie.

JAK DODAĆ MODELE:

1. Uruchom Rojo server:
   rojo serve

2. Otwórz Roblox Studio i połącz się z Rojo

3. W Studio, wejdź do: ReplicatedStorage > ItemModels

4. Stwórz MODELE (nie foldery!) z następującymi nazwami:
   - FlashlightModel (Model z PrimaryPart ustawionym!)
   - KeyModel
   - BatteryModel
   - LockpickModel
   - MedkitModel

5. Każdy model MUSI mieć:
   - PrimaryPart ustawione (kliknij prawym na Model > Set PrimaryPart)
   - Części mogą mieć dowolne kształty/kolory
   - Model zostanie automatycznie zsynchronizowany przez Rojo

WAŻNE:
- NIE twórz plików .json w tym folderze ręcznie!
- Rojo automatycznie śledzi zmiany w Studio
- Jeśli model nie pojawia się, sprawdź czy Rojo server działa

PRZYKŁADOWA STRUKTURA MODELU:

FlashlightModel (Model)
├─ Handle (Part) ← Set as PrimaryPart
├─ Lens (Part)
└─ Body (Part)

