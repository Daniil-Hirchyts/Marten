require 'xcodeproj'
project_path = 'MartenIOSWrapper.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Remove SelectSinglePinboardIntent.swift from ALL targets in the xcodeproj
# because it's part of the MartenIOSApp library dependency.
project.targets.each do |target|
  target.source_build_phase.files_references.each do |ref|
    if ref.name == 'SelectSinglePinboardIntent.swift' || File.basename(ref.path) == 'SelectSinglePinboardIntent.swift'
      target.source_build_phase.remove_file_reference(ref)
    end
  end
end

project.save
