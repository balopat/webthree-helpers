#!/usr/bin/env bash

# solves problem with macdeployqt on Qt 5.4 RC and Qt 5.5
# http://qt-project.org/forums/viewthread/50118

BUILD_FOLDER_PATH=$1
BUILD_QML_FOLDER_PATH="$BUILD_FOLDER_PATH/Resources/qml"
BUILD_PLUGINS_FOLDER_PATH="$BUILD_FOLDER_PATH/PlugIns"

if [ -d ${BUILD_QML_FOLDER_PATH} ]; then

	declare -a BROKEN_FILES;
	k=0;
	for j in $(find ${BUILD_QML_FOLDER_PATH} -name *.dylib); do
		BROKEN_FILES[${k}]=$j		
		((k=k+1))
	done


	for i in "${BROKEN_FILES[@]}"; do
		REPLACE_STRING="$BUILD_FOLDER_PATH/"
		APP_CONTENT_FILE=${i//$REPLACE_STRING/""}
		IFS='/' read -a array <<< "$APP_CONTENT_FILE"
		LENGTH=${#array[@]}
		LAST_ITEM_INDEX=$((LENGTH-1))
		FILE=${array[${LENGTH} - 1]}
		
		ORIGINE_PATH=$(find ${BUILD_PLUGINS_FOLDER_PATH} -name ${FILE})
		ORIGINE_PATH=${ORIGINE_PATH//$REPLACE_STRING/""}
		s=""
		for((l=0;l<${LAST_ITEM_INDEX};l++)) do
			s=$s"../"
		done
		s=$s$ORIGINE_PATH
		echo "s: $s"
		
		REMOVE_BROKEN_ALIAS=$(rm -rf $i)
		RESULT=$(ln -s $s $i)
	done
fi

# replace framework links 

# July 3rd Balint Pato - libleveldb seems to be referring to libsnappy which makes verify_app fail
install_name_tool -change /usr/local/lib/libsnappy.1.dylib @executable_path/../Frameworks/libsnappy.1.dylib  $BUILD_FOLDER_PATH/Frameworks/libleveldb.1.dylib

declare -a BROKEN_FRAMEWORKS;
k=0;
BUILD_FRAMEWORKS_FOLDER_PATH="$BUILD_FOLDER_PATH/Frameworks"
for j in $(find ${BUILD_FRAMEWORKS_FOLDER_PATH} -name Qt*.framework); do
	BROKEN_FRAMEWORKS[${k}]=$j
	((k=k+1))
done
for i in "${BROKEN_FRAMEWORKS[@]}"; do
	# fix external references from Qt framework binaries
	FRAMEWORK_FILE=$i/$(basename -s ".framework" $i)	
	otool -L $FRAMEWORK_FILE | grep -o /usr/.*Qt.*framework/[^\ ]* | while read -a libs ; do
		QT5FRAMEWORK=`basename ${libs[0]}`
		install_name_tool -change ${libs[0]} @loader_path/../../../$QT5FRAMEWORK.framework/$QT5FRAMEWORK $FRAMEWORK_FILE
	done

	# This next loop also fixes apps included *inside* these frameworks in the same way. Currently, only QtWebEngineProcess.app inside QtWebEngineCore
	# is affected, but trying to keep this general in case more slip through in the future.
	# This is due to a known bug in QT5, and we have to fix up the linked libraries if we're going to have a distributable
	# result of building. When https://bugreports.qt.io/browse/QTBUG-50155 is fixed, this should be able
	# to be removed.
	#
	# Bob Summerwill added an extra hack into this loop on 2nd March specifically for
	# libdbus, which is used by the GUI apps from within Qt5.  The hacks-on-hacks which
	# we have make this code an absolute morass to understand.  Ideally we wouldn't
	# need this script at all, and maybe the need for it will disappear if we can
	# eliminate the need for "--with-d-bus" for our Qt5 usage, which then forces us
	# to build from source.
	#
	# We have had open tickets in the Qt project, in the Homebrew project itself,
	# in our brew formula and now here in this script.   It is a nightmare.  This
	# most recent hack seems to get us working, but it is by no means a good
	# solution.   Nothing in this whole chain-of-hacks is good.
	#
	# Yes - the dylib filename is specific to the D-Bus version.   We will never
	# reuse this script.  It needs to work, and not a lot more than that.
		
	for j in $(find $i -name \*\.app); do
		# replacing references to /usr/.../Qt* in internal executables (e.g. QtWebEngineProcess within Mix-ide) 
		EXEC_NAME=$j/Contents/MacOS/$(basename -s .app $j)
		otool -L $EXEC_NAME | grep -o /usr/local.*dylib | while read -a innerlibs ; do	
			INNER_LIB=`basename ${innerlibs[0]}`
			install_name_tool -change ${innerlibs[0]} @executable_path/../../../../../../../../Frameworks/$INNER_LIB $EXEC_NAME
		done

		# replacing references to /usr/.../Qt* in libraries of internal executables (e.g. QtWebEngineProcess within Mix-ide refers to QtGui) 
		otool -L $EXEC_NAME | grep -o /usr/.*Qt.*framework/[^\ ]* | while read -a qt5libs ; do
			QT5FRAMEWORK=`basename ${qt5libs[0]}`		
			# note $QT5FRAMEWORK.framework/Version/5/$QT5FRAMEWORK instead of the symlink of $QT5FRAMEWORK.framework/$QT5FRAMEWORK  
			# it's important as even though it would resolve the library - but when the library refers to another library (which we fix at the FRAMEWORK_FILE loop)
			# it would resolve to two levels in the wrong place - as @loader_path is not using the version symlink (hence the ../../../ instead of ../)
	       	install_name_tool -change ${qt5libs[0]} @executable_path/../../../../../../../../Frameworks/$QT5FRAMEWORK.framework/Versions/5/$QT5FRAMEWORK $EXEC_NAME
		done
		
		install_name_tool -change @loader_path/../Frameworks/libdbus-1.3.dylib @executable_path/../../../../../../../../Frameworks/libdbus-1.3.dylib $EXEC_NAME

	done
done

declare -a BROKEN_PLUGINS;
k=0;
BUILD_PLUGINS_FOLDER_PATH="$BUILD_FOLDER_PATH/PlugIns"
for j in $(find ${BUILD_PLUGINS_FOLDER_PATH} -name *.dylib); do
	BROKEN_PLUGINS[${k}]=$j
	((k=k+1))
done
for i in "${BROKEN_PLUGINS[@]}"; do
	FRAMEWORK_FILE=$i
	otool -L $FRAMEWORK_FILE | grep -o /usr/.*Qt.*framework/[^\ ]* | while read -a libs ; do
			QT5FRAMEWORK=`basename ${libs[0]}`
	       	install_name_tool -change ${libs[0]} @loader_path/../../Frameworks/$QT5FRAMEWORK.framework/$QT5FRAMEWORK $FRAMEWORK_FILE
	done
done
