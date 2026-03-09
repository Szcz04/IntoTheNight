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
- Rojo domyślnie synchronizuje głównie z plików -> Studio (nie odwrotnie).
- Modele stworzone tylko w Studio mogą zostać usunięte przy kolejnym sync, jeśli nie są mapowane.
- Ten projekt ma ustawione $ignoreUnknownInstances dla ItemModels i ReplicatedStorage,
  więc modele dodane w Studio powinny już być zachowane.
- Najbezpieczniej trzymaj docelowe assety jako pliki w repo (np. eksport .rbxm/.rbxmx).

PRZYKŁADOWA STRUKTURA MODELU:

FlashlightModel (Model)
├─ Handle (Part) ← Set as PrimaryPart
├─ Lens (Part)
└─ Body (Part)

