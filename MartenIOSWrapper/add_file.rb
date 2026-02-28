require 'xcodeproj'
project_path = 'MartenIOSWrapper.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MartenWidgetsExtension' }
group = project.main_group.find_subpath(File.join('MartenWidgetsExtension'), true)
file_ref = group.new_reference('MartenControlWidgets.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
