require 'xcodeproj'
project_path = 'MartenIOSWrapper.xcodeproj'
project = Xcodeproj::Project.open(project_path)

widget_target = project.targets.find { |t| t.name == 'MartenWidgetsExtension' }

group = project.main_group.find_subpath(File.join('MartenWidgetsExtension'), true)
file_ref1 = group.new_reference('MartenControlWidgets.swift')
file_ref2 = group.new_reference('MartenPinboardItemsWidget.swift')

if widget_target
  widget_target.source_build_phase.add_file_reference(file_ref1)
  widget_target.source_build_phase.add_file_reference(file_ref2)
end

project.save
