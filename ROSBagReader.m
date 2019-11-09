classdef ROSBagReader < matlab.mixin.Copyable
    % Author: Rahul Bhadani
    % Maintainer Email: rahulbhadani@email.arizona.edu
    % License: MIT License 
    % Copyright 2019-2020 Rahul Bhadani
    % Initial Date: Sept 12, 2019
    % Permission is hereby granted, free of charge, to any person obtaining 
    % a copy of this software and associated documentation files 
    % (the "Software"), to deal in the Software without restriction, including
    % without limitation the rights to use, copy, modify, merge, publish,
    % distribute, sublicense, and/or sell copies of the Software, and to 
    % permit persons to whom the Software is furnished to do so, subject 
    % to the following conditions:

    % The above copyright notice and this permission notice shall be 
    % included in all copies or substantial portions of the Software.

    % THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF 
    % ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
    % TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A 
    % PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT 
    % SHALL THE AUTHORS, COPYRIGHT HOLDERS OR ARIZONA BOARD OF REGENTS
    % BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN 
    % AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
    % OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
    % OR OTHER DEALINGS IN THE SOFTWARE.
    
    
    % Description 
    % This is a matlab class called as ROSBagReader that reads a bag file
    % and extracts data in CSV and MAT format.
    
    %% Properties
    properties
        bagfile; % Full path of the bag  file, e.g /home/ece446/2019-08-21-22-00-00.bag
        filename; % Name of the bag file 2019-08-21-22-00-00.bag
        dir; % Directory where bag file is located
        bagReader;
        topicTable;
        availableTopics;
        numMessages;
        messageType;
        datafolder;
    end
    
    %% Methods
    methods
        %% Constructors
        function obj = ROSBagReader(file)
            
            % Clip ./ if file starts with ./
            if contains(file, './')
                file = file(3:end);
            end
            
            if nargin == 1
                obj.bagfile = file;
                
                if ismac || isunix
                    slashIndices = strfind(file, '/');
                elseif ispc
                    slashIndices = strfind(file, '\');
                end
                if ~isempty(slashIndices)
                    obj.filename = file(slashIndices(end)+1: end);
                else
                    obj.filename = file;
                end

                if ~isempty(slashIndices)
                    obj.dir = file(slashIndices(1): slashIndices(end));
                else
                    obj.dir = '';
                end


                fprintf('\nReading the bag file %s\n\n', file);
                obj.bagReader = rosbag(file);
                obj.topicTable = obj.bagReader.AvailableTopics; % Get the topic table
                obj.availableTopics = obj.bagReader.AvailableTopics.Row; % Store the available Topic
                obj.numMessages = obj.bagReader.AvailableTopics.NumMessages; % store number of messages for each topic
                obj.messageType = obj.bagReader.AvailableTopics.MessageType; % Store message type for each topic
                
                if ismac || isunix
                    obj.datafolder = strcat(obj.dir ,obj.filename(1:end-4),'/');
                elseif ispc
                    obj.datafolder = strcat(obj.dir ,obj.filename(1:end-4),'\');
                end
                
                
                [~, ~, msgID] =  mkdir(obj.datafolder );
                if( strcmp(msgID, 'MATLAB:MKDIR:DirectoryExists') )
                    fprintf('\nData folder for %s already exists.\n\n', file);
                end
                
            else
                aac = matlab.lang.correction.AppendArgumentsCorrection('"bagfilefullpath"');
                error(aac, 'MATLAB:notEnoughInputs', 'Too many input arguments.')  
            end
        end
        
        % Function to extract  Laser Scan Data and save in the file where
        % rosbag file is located
        function extractLaserData(obj)
            
            % Note down the index of laserscan messages from table topic
            % Note that there can be multiple topics of
            % sensor_msgs/LaserScan type. extractLaserData function
            % retrieves all such topics of type sensor_msgs/LaserScan
            index_scan = obj.messageType == 'sensor_msgs/LaserScan';
            
            % find all the topics of type sensor_msgs/LaserScan
            topic_of_scan = obj.availableTopics(index_scan);
            num_msgs = obj.numMessages(index_scan);
            % Now we will iterate over all the topics and retrieve data
            % from every topic of message type sensor_msgs/LaserScan
            % and save them in mat format as well as csv format
            for i = 1:length(topic_of_scan)
                topic_to_read = topic_of_scan{i};
                fprintf('\nReading the Laser Scan messages on the topic %s\n\n', topic_to_read);
                
                % Select object that selects particular topic from rosbag object
                 scan_select = select(obj.bagReader, 'Topic', topic_to_read);

                % Save all messages from this topic in an struct format
                msgStructs = readMessages(scan_select,'DataFormat','struct');
                
                % since ROS topic names contain slashes, we will replace
                % every slash with a dash. This topic name will be used to
                % create the mat file, meaning mat file that saves message
                % has same name as the corresponding topic         
                topic_to_save = strrep(topic_to_read(2:end),'/','-');
                
                % Now save the retrieved data in the datafolder
                matfile = strcat(obj.datafolder, topic_to_save,'.mat');
                
                save(matfile,'msgStructs');

                fprintf('Writing Laser Scan Data  to file %s from topic %s completed!!\n\n', matfile, topic_to_read);

                                
                num_messages = num_msgs(i);
                
                
                % Here, we are finding maximum number of datapoints in the  
                % range data among all the scan samples. If a range data of
                % any sample has less number of points than others, then we
                % will just append NaN at the end. The reason we agere doing
                % is because of efficiency as it is more time consuming to
                % read staggered matrix than a rectangular matrix.
                Len = [];
                for i = 1:num_messages
                    Len = [Len, length(msgStructs{i}.Ranges)];
                end
                maxLen = max(Len);
                Data = string(zeros(num_messages, maxLen + 1));
                for i = 1:num_messages
                    
                    tempLen = length(msgStructs{i}.Ranges);
                    
                    % We are doing this because for a particular timestep,
                    % there are less than maxLen datapoints
                    if(tempLen < maxLen)
                         NaNPOSTFIX = zeros( maxLen - tempLen, 1)*NaN;
                         msgStructs{i}.Ranges = [msgStructs{i}.Ranges; NaNPOSTFIX];
                    end
                    
                    secondtime = double(msgStructs{i}.Header.Stamp.Sec)+double(msgStructs{i}.Header.Stamp.Nsec)*10^-9;
                    Data(i, 1) = secondtime;
                    Data(i, 2:end) = transpose(msgStructs{i}.Ranges);
                end
                
                csvfile = strcat(obj.datafolder, topic_to_save,'.csv');
                
                % Support for version older than 2019
                if contains(version, '2019')
                    writematrix(Data,csvfile,'Delimiter',',');
                else
                    T = array2table(Data);
                    writetable(T, csvfile, 'WriteVariableNames',0);
                end
                fprintf('Writing Laser Scan Data  to file %s from topic %s completed!!\n\n', csvfile, topic_to_read);
                
            end
            
        end % end of extractLaserData
        
        % Function to extract  Velocity Data and save in the file where
        % rosbag file is located
        function [CSV, MAT] = extractVelData(obj, varargin)
            
            start_time = 0.0;
            end_time = 0.0;
            CSV  = {};
            MAT = {};
            if length(varargin) > 2
                error("Too Many Input Arguments. Expecting only initial time and end time");  
            elseif  length(varargin) == 2
                start_time = varargin(1);
                start_time = start_time{1};
                end_time = varargin(2);
                end_time = end_time{1};
            end
            
            % Note down the index of twist messages from table topic
            % Note that there can be multiple topics of
            % geometry_msgs/Twist type. extractVelData function
            % retrieves all such topics of type geometry_msgs/Twist
            index_twist = obj.messageType == 'geometry_msgs/Twist';
            
            % find all the topics of type geometry_msgs/Twist
            topic_of_twist = obj.availableTopics(index_twist);
            if(isempty(topic_of_twist))
                fprintf('\nNo velocity messages found.\n\n');
                return;
            end
            % Now we will iterate over all the topics and retrieve data
            % from every topic of message type geometry_msgs/Twist
            % and save them in mat format as well as csv format
            MAT = cell(1,  length(topic_of_twist));
            CSV = cell(1,  length(topic_of_twist));
            for i = 1:length(topic_of_twist)
                topic_to_read = topic_of_twist{i};
                fprintf('\nReading the Velocity messages on the topic %s\n\n', topic_to_read);
                
                % Select object that selects particular topic from rosbag object
                 twist_select = select(obj.bagReader, 'Topic', topic_to_read);

                % Save messages in timeseries format
                velData = timeseries(twist_select);
                
                % Get the first time stamp
                initial_ros_time = velData.Time(1);
                
                if length(varargin) == 2
                                        
                    % Get the total duration of the captured message
                    total_duration = velData.Time(end) - initial_ros_time;
                    if(end_time > total_duration)
                        warning(sprintf("End time specified exceeds the total duration of the captured message.\nExtracting upto maximum duration only."));
                        end_time = total_duration;
                    end
                    
                    % Select object that selects particular topic from
                    % rosbag object with specified time duration
                    twist_select = select(obj.bagReader, 'Topic', topic_to_read, 'Time', [start_time + initial_ros_time, end_time + initial_ros_time ]);

                    % Save messages in timeseries format
                    velData = timeseries(twist_select);

                end
                                
                % since ROS topic names contain slashes, we will replace
                % every slash with a dash. This topic name will be used to
                % create the mat file, meaning mat file that saves message
                % has same name as the corresponding topic           
                topic_to_save = strrep(topic_to_read(2:end),'/','-');
                
                % Now save the retrieved data in the datafolder
                matfile = strcat(obj.datafolder, topic_to_save,'.mat');
                MAT{i} = matfile;
                save(matfile,'velData');

                fprintf('Writing Velocity Data  to file %s from topic %s completed!!\n\n', matfile, topic_to_read);

                Data = string([velData.Time, velData.Data]);
                
                 % Now save the retrieved data in the datafolder in csv
                 % format
                csvfile = strcat(obj.datafolder, topic_to_save,'.csv');
                CSV{i} = csvfile;
                 % Support for version older than 2019
                if contains(version, '2019')
                    writematrix(Data,csvfile,'Delimiter',',');
                else
                    T = array2table(Data);
                    writetable(T, csvfile, 'WriteVariableNames',0);
                end
                
                 fprintf('Writing Velocity Data  to file %s from topic %s completed!!\n\n', csvfile, topic_to_read);
                
            end
            
        end % end of extractVelData
        
        % Function to extract  Camera Compressed Images and save in the file where
        % rosbag file is located
        function extractCompressedImages(obj)
            
            % Note down the index of laserscan messages from table topic
            % Note that there can be multiple topics of
            %  sensor_msgs/CompressedImage type. extractCompressedImages function
            % retrieves all such topics of type  sensor_msgs/CompressedImage
            index_scan = obj.messageType == 'sensor_msgs/CompressedImage';
            
            % find all the topics of type sensor_msgs/LaserScan
            topic_of_scan = obj.availableTopics(index_scan);
            num_msgs = obj.numMessages(index_scan);
            % Now we will iterate over all the topics and retrieve data
            % from every topic of message type  sensor_msgs/CompressedImage
            % and save them in mat format as well as csv format
            for i = 1:length(topic_of_scan)
                topic_to_read = topic_of_scan{i};
                fprintf('\nReading the Compressed Image messages on the topic %s\n\n', topic_to_read);
                
                % Select object that selects particular topic from rosbag object
                scan_select = select(obj.bagReader, 'Topic', topic_to_read);

                % Retrieve messages from this topic in an struct format
                msgStructs = readMessages(scan_select);
                % since ROS topic names contain slashes, we will replace
                % every slash with a dash. This topic name will be used to
                % create the mat file, meaning mat file that saves message
                % has same name as the corresponding topic             
                topic_to_save = strrep(topic_to_read(2:end),'/','-');
                
                figurefolder  = strcat(obj.datafolder,'/',topic_to_save) ;
                [~, ~, msgID] =  mkdir(figurefolder);
                if( strcmp(msgID, 'MATLAB:MKDIR:DirectoryExists') )
                    fprintf('\nFolder %s already exists.\n\n', figurefolder);
                end
                                
                num_messages = num_msgs(i);
                                
                for i = 1:num_messages
                    secondtime = double(msgStructs{i}.Header.Stamp.Sec)+double(msgStructs{i}.Header.Stamp.Nsec)*10^-9;
                    image = readImage(msgStructs{i});
                    imwrite(image, strcat(figurefolder, '/', string(secondtime) , '.png'));
                end
                
                fprintf('Compressed Image extraction  to the folder %s from topic %s completed!!\n\n', figurefolder, topic_to_read);
                                
            end
            
        end % end of extractCompressedImages
        
        
        % Function to extract  Odometry Data and save in the file where
        % rosbag file is located
        function [CSV, MAT]  = extractOdometryData(obj)
            
            CSV  = {};
            MAT = {};
            
            % Note down the index of twist messages from table topic
            % Note that there can be multiple topics of
            % nav_msgs/Odometry  type. extractOdometryData function
            % retrieves all such topics of type nav_msgs/Odometry 
            index_odom= obj.messageType == 'nav_msgs/Odometry';
            num_msgs = obj.numMessages(index_odom);
            % find all the topics of type nav_msgs/Odometry 
            topic_of_odom = obj.availableTopics(index_odom);
            if(isempty(topic_of_odom))
                fprintf('\nNo velocity messages found.\n\n');
                return;
            end
            % Now we will iterate over all the topics and retrieve data
            % from every topic of message type nav_msgs/Odometry
            % and save them in mat format as well as csv format
            MAT = cell(1,  length(topic_of_odom));
            CSV = cell(1,  length(topic_of_odom));
            
            for i = 1:length(topic_of_odom)
                topic_to_read = topic_of_odom{i};
                fprintf('\nReading the Odometry messages on the topic %s\n\n', topic_to_read);
                
                % Select object that selects particular topic from rosbag object
                odom_select = select(obj.bagReader, 'Topic', topic_to_read);
                
                % since ROS topic names contain slashes, we will replace
                % every slash with a dash. This topic name will be used to
                % create the mat file, meaning mat file that saves message
                % has same name as the corresponding topic           
                topic_to_save = strrep(topic_to_read(2:end),'/','-');
                
                msgStructs = readMessages(odom_select);
                
                % Now save the retrieved data in the datafolder
                matfile = strcat(obj.datafolder, topic_to_save,'.mat');
                
                MAT{i} = matfile;
                
                save(matfile,'msgStructs');

                fprintf('Writing Odometry Data  to file %s from topic %s completed!!\n\n', matfile, topic_to_read);
                
                num_messages = num_msgs(i);

                %%%%%%%%
                inum = 1;
                secondtime = double(msgStructs{inum}.Header.Stamp.Sec)+double(msgStructs{inum}.Header.Stamp.Nsec)*10^-9;
                sequence = msgStructs{inum}.Header.Seq;
                frameId = string(msgStructs{inum}.Header.FrameId);
                childFrameId = string(msgStructs{inum}.ChildFrameId);
                PoseX = msgStructs{inum}.Pose.Pose.Position.X;
                PoseY = msgStructs{inum}.Pose.Pose.Position.Y;
                PoseZ = msgStructs{inum}.Pose.Pose.Position.Z;
                OrientationX =msgStructs{inum}.Pose.Pose.Orientation.X;
                OrientationY = msgStructs{inum}.Pose.Pose.Orientation.Y;
                OrientationZ = msgStructs{inum}.Pose.Pose.Orientation.Z;
                OrientationW = msgStructs{inum}.Pose.Pose.Orientation.W;
                LinearX = msgStructs{inum}.Twist.Twist.Linear.X;
                LinearY = msgStructs{inum}.Twist.Twist.Linear.Y;
                LinearZ = msgStructs{inum}.Twist.Twist.Linear.Z;
                AngularX = msgStructs{inum}.Twist.Twist.Angular.X;
                AngularY = msgStructs{inum}.Twist.Twist.Angular.Y;
                AngularZ = msgStructs{inum}.Twist.Twist.Angular.Z;

                PoseCov = msgStructs{inum}.Pose.Covariance;
                TwistCov =msgStructs{inum}.Twist.Covariance;
                
                num_columns = length(secondtime) + length(sequence) + length(frameId) + length(childFrameId) + ...
                    length(PoseX) + length(PoseY) + length(PoseZ) + length(OrientationX) + length(OrientationY) + ...
                    length(OrientationZ) + length(OrientationW) + length(LinearX) + length(LinearY) + ...
                    length(LinearZ) + length(AngularX) + length(AngularY) + length(AngularZ) + ...
                    length(PoseCov) + length(TwistCov);
                    
                Data = string(zeros(num_messages+1, num_columns));
                
                Header = string(zeros(1,  num_columns));
                Header(:, 1:17) = ["Time", "SequenceID", "FrameID", "ChildFrameID", "PoseX", "PoseY", "PoseZ", "OrientationX",...
                    "OrientationY", "OrientationZ", "OrientationW", "LinearX", "LinearY", "LinearZ", ...
                    "AngularX", "AngularY", "AngularZ"];
                
    %            Header(:, 18:18+length(PoseCov)-1) = strcat(repmat("PoseCov",1,length(PoseCov)), num2str(1:length(PoseCov)));
                
                for j = 1:length(PoseCov)
                    Header(:, 17+j) =  strcat("PoseCov", num2str(j));
                end

%                Header(:, 18+length(PoseCov):18+length(PoseCov) + length(TwistCov)-1) = strcat(repmat("TwistCov",1,length(TwistCov)), num2str(1:length(TwistCov)));

        
                for j = 1:length(TwistCov)
                    Header(:,17+j+length(TwistCov)) = strcat("TwistCov", num2str(j));
                end
                
                Data(1, :) = Header;
                
                for inum = 1:num_messages
                    
                    secondtime = double(msgStructs{inum}.Header.Stamp.Sec)+double(msgStructs{inum}.Header.Stamp.Nsec)*10^-9;
                    sequence = msgStructs{inum}.Header.Seq;
                    frameId = string(msgStructs{inum}.Header.FrameId);
                    childFrameId = string(msgStructs{inum}.ChildFrameId);
                    PoseX = msgStructs{inum}.Pose.Pose.Position.X;
                    PoseY = msgStructs{inum}.Pose.Pose.Position.Y;
                    PoseZ = msgStructs{inum}.Pose.Pose.Position.Z;
                    OrientationX =msgStructs{inum}.Pose.Pose.Orientation.X;
                    OrientationY = msgStructs{inum}.Pose.Pose.Orientation.Y;
                    OrientationZ = msgStructs{inum}.Pose.Pose.Orientation.Z;
                    OrientationW = msgStructs{inum}.Pose.Pose.Orientation.W;
                    LinearX = msgStructs{inum}.Twist.Twist.Linear.X;
                    LinearY = msgStructs{inum}.Twist.Twist.Linear.Y;
                    LinearZ = msgStructs{inum}.Twist.Twist.Linear.Z;
                    AngularX = msgStructs{inum}.Twist.Twist.Angular.X;
                    AngularY = msgStructs{inum}.Twist.Twist.Angular.Y;
                    AngularZ = msgStructs{inum}.Twist.Twist.Angular.Z;
                    
                    PoseCov = transpose(msgStructs{inum}.Pose.Covariance);
                    TwistCov =transpose(msgStructs{inum}.Twist.Covariance);
                    
                    Data(inum+1, :) = [secondtime, sequence, frameId, childFrameId, PoseX,PoseY, PoseZ, ...
                        OrientationX, OrientationY, OrientationZ, OrientationW, LinearX, LinearY, LinearZ,...
                        AngularX, AngularY, AngularZ, PoseCov, TwistCov];
                end
                
                 % Now save the retrieved data in the datafolder in csv
                 % format
                csvfile = strcat(obj.datafolder, topic_to_save,'.csv');
                CSV{i} = csvfile;
                
                % Support for version older than 2019
                if contains(version, '2019')
                    writematrix(Data,csvfile,'Delimiter',',');
                else
                    T = array2table(Data);
                    writetable(T, csvfile, 'WriteVariableNames',0);
                end
                
                fprintf('Writing Odometry Data  to file %s from topic %s completed!!\n\n', csvfile, topic_to_read);
                
            end
            
        end % end of extractOdometryData
        
        % Function to extract  Wrench Data and save in the file where
        % rosbag file is located
        function extractWrenchData(obj)
            
            % Note down the index of Wrench messages from table topic
            % Note that there can be multiple topics of
            % geometry_msgs/Wrench type. extractWrenchData function
            % retrieves all such topics of type geometry_msgs/Wrench
            index_wrench = obj.messageType == 'geometry_msgs/Wrench';
            
            % find all the topics of type geometry_msgs/Wrench
            topic_of_wrench = obj.availableTopics(index_wrench);
            if(isempty(topic_of_wrench))
                fprintf('\nNo Wrench messages found.\n\n');
                return;
            end
            % Now we will iterate over all the topics and retrieve data
            % from every topic of message type geometry_msgs/Wrench
            % and save them in mat format as well as csv format
            for i = 1:length(topic_of_wrench)
                topic_to_read = topic_of_wrench{i};
                fprintf('\nReading the Wrench messages on the topic %s\n\n', topic_to_read);
                
                % Select object that selects particular topic from rosbag object
                 wrench_select = select(obj.bagReader, 'Topic', topic_to_read);

                % Save messages in timeseries format
                wrenchData = timeseries(wrench_select);
                
                % since ROS topic names contain slashes, we will replace
                % every slash with a dash. This topic name will be used to
                % create the mat file, meaning mat file that saves message
                % has same name as the corresponding topic           
                topic_to_save = strrep(topic_to_read(2:end),'/','-');
                
                % Now save the retrieved data in the datafolder
                matfile = strcat(obj.datafolder, topic_to_save,'.mat');
                
                save(matfile,'wrenchData');

                fprintf('Writing Wrench Data  to file %s from topic %s completed!!\n\n', matfile, topic_to_read);

                Data = string([wrenchData.Time, wrenchData.Data]);
                
                 % Now save the retrieved data in the datafolder in csv
                 % format
                csvfile = strcat(obj.datafolder, topic_to_save,'.csv');
                 % Support for version older than 2019
                if contains(version, '2019')
                    writematrix(Data,csvfile,'Delimiter',',');
                else
                    T = array2table(Data);
                    writetable(T, csvfile, 'WriteVariableNames',0);
                end
                
                fprintf('Writing Wrench Data  to file %s from topic %s completed!!\n\n', csvfile, topic_to_read);
                
            end
            
        end % end of extractwrenchData
        
         % Function to extract  Clock Data of type rosgraph_msgs/Clock and save in the file where
        % rosbag file is located
        function extractClockData(obj)
            
            % Note down the index of Clock messages from table topic
            % Note that there can be multiple topics of
            % rosgraph_msgs/Clock type. extractClockData function
            % retrieves all such topics of type rosgraph_msgs/Clock
            index_Clock = obj.messageType == 'rosgraph_msgs/Clock';
            CSV  = {};
            MAT = {};
            % find all the topics of type rosgraph_msgs/Clock
            topic_of_clock = obj.availableTopics(index_Clock);
            if(isempty(topic_of_clock))
                fprintf('\nNo Clock messages found.\n\n');
                return;
            end
            % Now we will iterate over all the topics and retrieve data
            % from every topic of message type rosgraph_msgs/Clock
            % and save them in mat format as well as csv format
            MAT = cell(1,  length(topic_of_clock));
            CSV = cell(1,  length(topic_of_clock));
            for i = 1:length(topic_of_clock)
                topic_to_read = topic_of_clock{i};
                fprintf('\nReading the Clock messages on the topic %s\n\n', topic_to_read);
                
                % Select object that selects particular topic from rosbag object
                 clock_select = select(obj.bagReader, 'Topic', topic_to_read);

                % Save messages in timeseries format
                clockData = timeseries(clock_select);
                
                % since ROS topic names contain slashes, we will replace
                % every slash with a dash. This topic name will be used to
                % create the mat file, meaning mat file that saves message
                % has same name as the corresponding topic           
                topic_to_save = strrep(topic_to_read(2:end),'/','-');
                
                % Now save the retrieved data in the datafolder
                matfile = strcat(obj.datafolder, topic_to_save,'.mat');
                MAT{i} = matfile;
                save(matfile,'clockData');

                fprintf('Writing Clock Data  to file %s from topic %s completed!!\n\n', matfile, topic_to_read);

                Data_Headless = string([clockData.Time, clockData.Data]);
                Header = ["Time", "Secs","Nsecs"];
                Data = [Header   ; Data_Headless];
                
                 % Now save the retrieved data in the datafolder in csv
                 % format
                csvfile = strcat(obj.datafolder, topic_to_save,'.csv');
                CSV{i} = csvfile;
                 % Support for version older than 2019
                if contains(version, '2019')
                    writematrix(Data,csvfile,'Delimiter',',');
                else
                    T = array2table(Data);
                    writetable(T, csvfile, 'WriteVariableNames',0);
                end
                
                fprintf('Writing Clock Data  to file %s from topic %s completed!!\n\n', csvfile, topic_to_read);
                
            end
            
        end % end of extractClockData
        
    end % end of methods
    
            
end % of classdef

    
