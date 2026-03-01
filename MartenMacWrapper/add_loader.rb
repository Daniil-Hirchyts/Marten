require 'xcodeproj'
project_path = 'MartenMacWrapper.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Marten' }
group = project.main_group.find_subpath('Marten', true)
file_ref = group.new_reference('../MartenMac/Sources/MartenMacApp/UI/Overlay/LinkPreviewImageLoader.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
