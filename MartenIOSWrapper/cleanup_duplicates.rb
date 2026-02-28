require 'xcodeproj'
project_path = 'MartenIOSWrapper.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'MartenWidgetsExtension' }

if target
  # Remove all instances of these files from the build phase
  files_to_de_duplicate = [
    'MartenControlWidgets.swift',
    'MartenPinboardItemsWidget.swift',
    'SelectSinglePinboardIntent.swift'
  ]
  
  target.source_build_phase.files.each do |build_file|
    if build_file.file_ref && files_to_de_duplicate.include?(build_file.file_ref.name || File.basename(build_file.file_ref.path))
       # We will re-add them once correctly
    end
  end
  
  # Actually, let's just find and remove them all, then add back once.
  # But for SelectSinglePinboardIntent.swift, we should NOT add it to the extension target 
  # because it's already in the MartenIOSApp package dependency.
  
  target.source_build_phase.files_references.each do |ref|
     if files_to_de_duplicate.include?(ref.name || File.basename(ref.path))
       target.source_build_phase.remove_file_reference(ref)
     end
  end

  # Re-add only the necessary ones for the Widget target
  group = project.main_group.find_subpath(File.join('MartenWidgetsExtension'), true)
  
  ref1 = group.find_file_by_path('MartenControlWidgets.swift') || group.new_reference('MartenControlWidgets.swift')
  target.source_build_phase.add_file_reference(ref1)
  
  ref2 = group.find_file_by_path('MartenPinboardItemsWidget.swift') || group.new_reference('MartenPinboardItemsWidget.swift')
  target.source_build_phase.add_file_reference(ref2)
  
  # SelectSinglePinboardIntent.swift is NOT added here.
end

project.save
