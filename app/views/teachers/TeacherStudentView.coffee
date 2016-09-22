RootView = require 'views/core/RootView'
Campaigns = require 'collections/Campaigns'
Classroom = require 'models/Classroom'
Courses = require 'collections/Courses'
Levels = require 'collections/Levels'
LevelSession = require 'models/LevelSession'
LevelSessions = require 'collections/LevelSessions'
User = require 'models/User'
Users = require 'collections/Users'
CourseInstances = require 'collections/CourseInstances'
require 'vendor/d3'



module.exports = class TeacherStudentView extends RootView
  id: 'teacher-student-view'
  template: require 'templates/teachers/teacher-student-view'
  # helper: helper
  events:
    # 'click .assign-student-button': 'onClickAssignStudentButton' # TODO: make this work
    # 'click .enroll-student-button': 'onClickEnrollStudentButton' # TODO: make this work
    'change #course-dropdown': 'onChangeCourseChart'



  getTitle: -> return @user?.broadName()

  initialize: (options, classroomID, @studentID) ->
    @classroom = new Classroom({_id: classroomID})
    @listenToOnce @classroom, 'sync', @onClassroomSync
    @supermodel.trackRequest(@classroom.fetch())

    @courses = new Courses()
    @supermodel.trackRequest(@courses.fetch({data: { project: 'name' }}))

    @courseInstances = new CourseInstances()
    @supermodel.trackRequest @courseInstances.fetchForClassroom(classroomID)

    @levels = new Levels()
    @supermodel.trackRequest(@levels.fetchForClassroom(classroomID, {data: {project: 'name,original'}}))
    @urls = require('core/urls')


    @singleStudentLevelProgressDotTemplate = require 'templates/teachers/hovers/progress-dot-single-student-level'
    @levelProgressMap = {}

    super(options)

  onLoaded: ->
    if @students.loaded and not @destroyed
      @user = _.find(@students.models, (s)=> s.id is @studentID)
      @updateLastPlayedString()
      @updateLevelProgressMap()
      @updateLevelDataMap()
      @calculateStandardDev()
      @render()
    super()

  afterRender: ->
    super(arguments...)
    $('.progress-dot, .btn-view-project-level').each (i, el) ->
      dot = $(el)
      dot.tooltip({
        html: true
        container: dot
      }).delegate '.tooltip', 'mousemove', ->
        dot.tooltip('hide')

    @drawBarGraph()
    @onChangeCourseChart()


  onChangeCourseChart: (e)->
    if (e)
      selected = ('#visualisation-'+((e.currentTarget).value))
      $("[id|='visualisation']").hide()
      $(selected).show()

  calculateStandardDev: ->
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded and @levelData

    @courseComparisonMap = []
    for versionedCourse in @classroom.get('courses') ? []
      course = _.find @courses.models, (c) => c.id is versionedCourse._id
      numbers = []
      studentRate = 0
      members = 0 #this is the COUNT for our standard deviation
      for member in @classroom.get('members')
        NUMBER = 0
        memberBit = 0
        for versionedLevel in versionedCourse.levels
          for session in @sessions.models
            if session.get('level').original is versionedLevel.original and session.get('creator') is member
              # TODO IMPORTANT: only add number if @studentID in levelProgressMap has complete or started for the corresponding level
              # in @levelData there's a levelProgress. If for this levelID, levelProgress = complete or started, go ahead.
              temp = _.findWhere(@levelData, {levelID: session.get('level').original})
              if temp.levelProgress is 'complete' or temp.levelProgress is 'started'
                NUMBER += session.get('playtime') or 0
                memberBit += 1
              if session.get('creator') is @studentID
                studentRate += session.get('playtime') or 0
        if memberBit > 0 then members += 1
        numbers.push NUMBER

      # add all numbers[]
      SUM = 0
      for num in numbers
        SUM += num

      # divide by members to get MEAN, remember MEAN is only an average of the members' performance on levels THIS student has done.
      MEAN = SUM/members

      # make new list diffSquared[]
      diffSquared = []

      # for each number in numbers[], subtract MEAN then SQUARE, put new number in diffSquared
      for num in numbers
        diffSquared.push ((num-MEAN)*(num-MEAN))

      # add all diffSquared[] then divide by COUNT to get VARIANCE
      diffSum = 0
      for num in diffSquared
        diffSum += num
      VARIANCE = (diffSum / members)

      # square root of VARIANCE is standardDev
      StandardDev = Math.sqrt(VARIANCE)

      perf = 0
      if studentRate > MEAN
        perf -=1
        if studentRate > (MEAN + StandardDev)
          perf -= 1
          if studentRate > (MEAN + (StandardDev*2))
            perf -=1
      else if studentRate < MEAN
        perf += 1
        if studentRate < (MEAN - StandardDev)
          perf +=1
          if studentRate < (MEAN - (StandardDev*2))
            perf +=1
      # perf 1 and -1 are within 1 std, perf 2 is AMAZING, perf -2 needs some help
      # can consider doing half of standard dev to capture more granularity

      @courseComparisonMap.push {
        courseID: course.get('_id')
        studentRate: studentRate
        standardDev: StandardDev
        mean: MEAN
        performance: perf
      }
    # console.log (@courseComparisonMap)

  # calculateStandardDev: ->
  #   return unless @courses.loaded and @levels.loaded and @sessions?.loaded
  #
  #   @courseComparisonMap = []
  #   for versionedCourse in @classroom.get('courses') ? []
  #     course = _.find @courses.models, (c) => c.id is versionedCourse._id
  #     # @courseTotal = 0
  #     @studentLevelsPlayed = 0 # count for standard deviation
  #     for versionedLevel in versionedCourse.levels
  #       @playTime = 0 # this should probably only count when the levels are completed
  #       # @timesPlayed = 0
  #       @studentTime = 0
  #       # @levelProgress = 'not started'
  #       for session in @sessions.models
  #         if session.get('level').original == versionedLevel.original
  #           # if @levelProgressMap[versionedLevel.original] == 'complete' # ideally, don't log sessions that aren't completed in the class
  #           @playTime += session.get('playtime') or 0
  #           # @timesPlayed += 1
  #           if session.get('creator') is @studentID
  #             @studentLevelsPlayed += 1
  #             @studentTime = session.get('playtime') or 0 # this can be null, apparently.
  #             # if @levelProgressMap[versionedLevel.original] == 'complete'
  #               # @levelProgress = 'complete'
  #             # else if @levelProgressMap[versionedLevel.original] == 'started'
  #               # @levelProgress = 'started'
  #             classAvg = if @timesPlayed and @timesPlayed > 0 then Math.round(@playTime / @timesPlayed) else 0 # only when someone other than the user has played
  #             # console.log (@timesPlayed)
  #             # @performance = if classAvg isnt 0  and @levelProgress isnt 'not started' then ((classAvg - @studentTime)/classAvg)*100 else 0
  #             # @courseTotal += @performance
  #
  #             @courseComparisonMap.push {
  #               courseID: course.get('_id')
  #               # rate: if @studentLevelsPlayed isnt 0 then (@courseTotal / @studentLevelsPlayed) else null
  #               studentRate: null
  #               standardDev: null
  #             }
  #   console.log (@courseComparisonMap)


  drawBarGraph: ->
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded and @levelData and @courseComparisonMap

    WIDTH = 1142
    HEIGHT = 600
    MARGINS = {
      top: 50
      right: 20
      bottom: 50
      left: 70
    }


    for versionedCourse in @classroom.get('courses') ? []
      # this does all of the courses, logic for whether student was assigned is in corresponding jade file
      vis = d3.select('#visualisation-'+versionedCourse._id)
      # TODO: continue if selector isn't found.
      courseLevelData = []
      for level in @levelData when level.courseID is versionedCourse._id
        courseLevelData.push level

      course = _.find @courses.models, (c) => c.id is versionedCourse._id
      levels = @classroom.getLevels({courseID: course.id}).models


      xRange = d3.scale.ordinal().rangeRoundBands([MARGINS.left, WIDTH - MARGINS.right], 0.1).domain(courseLevelData.map( (d) -> d.levelIndex))
      yRange = d3.scale.linear().range([HEIGHT - (MARGINS.top), MARGINS.bottom]).domain([0, d3.max(courseLevelData, (d) -> if d.classAvg > d.studentTime then d.classAvg else d.studentTime)])
      xAxis = d3.svg.axis().scale(xRange).tickSize(1).tickSubdivide(true)
      yAxis = d3.svg.axis().scale(yRange).tickSize(1).orient('left').tickSubdivide(true)

      vis.append('svg:g').attr('class', 'x axis').attr('transform', 'translate(0,' + (HEIGHT - (MARGINS.bottom)) + ')').call xAxis
      vis.append('svg:g').attr('class', 'y axis').attr('transform', 'translate(' + MARGINS.left + ',0)').call yAxis

      chart = vis.selectAll('rect')
        .data(courseLevelData)
        .enter()
      # draw classroom average bars
      chart.append('rect')
        .attr('class', 'classroom-bar')
        .attr('x', ((d) -> xRange(d.levelIndex) + (xRange.rangeBand())/2))
        .attr('y', (d) -> yRange(d.classAvg))
        .attr('width', (xRange.rangeBand())/2)
        .attr('height', (d) -> HEIGHT - (MARGINS.bottom) - yRange(d.classAvg))
        .attr('fill', '#5CB4D0')
      # add classroom average values
      chart.append('text')
        .attr('x', ((d) -> xRange(d.levelIndex) + (xRange.rangeBand())/2))
        .attr('y', ((d) -> yRange(d.classAvg) - 3 ))
        .text((d)-> if d.classAvg isnt 0 then d.classAvg)
        .attr('class', 'label')
      # draw student playtime bars
      chart.append('rect')
        .attr('class', 'student-bar')
        .attr('x', ((d) -> xRange(d.levelIndex)))
        .attr('y', (d) -> yRange(d.studentTime))
        .attr('width', (xRange.rangeBand())/2)
        .attr('height', (d) -> HEIGHT - (MARGINS.bottom) - yRange(d.studentTime))
        .attr('fill', (d) -> if d.levelProgress is 'complete' then '#20572B' else '#F2BE19')
      # add student playtime value
      chart.append('text')
        .attr('x', ((d) -> xRange(d.levelIndex)) )
        .attr('y', ((d) -> yRange(d.studentTime) - 3 ))
        .text((d)-> if d.studentTime isnt 0 then d.studentTime)
        .attr('class', 'label')

      labels = vis.append("g").attr("class", "labels")
      # add Playtime axis label
      labels.append("text")
        .attr("transform", "rotate(-90)")
        .attr("y", 20)
        .attr("x", - HEIGHT/2)
        .attr("dy", ".71em")
        .style("text-anchor", "middle")
        .text($.i18n.t("teacher.playtime_axis"))
      # add levels axis label
      labels.append("text")
        .attr("x", WIDTH/2)
        .attr("y", HEIGHT - 10)
        .text("Levels in " + (course.get('name')))
        .style("text-anchor", "middle")


  onClassroomSync: ->
    # Now that we have the classroom from db, can request all level sessions for this classroom
    @sessions = new LevelSessions()
    @sessions.comparator = 'changed' # Sort level sessions by changed field, ascending
    @listenTo @sessions, 'sync', @onSessionsSync
    @supermodel.trackRequests(@sessions.fetchForAllClassroomMembers(@classroom))

    @students = new Users()
    jqxhrs = @students.fetchForClassroom(@classroom, removeDeleted: true)
    # @listenTo @students, ->
    @supermodel.trackRequests jqxhrs

  onSessionsSync: ->
    # Now we have some level sessions, and enough data to calculate last played string
    # This may be called multiple times due to paged server API calls via fetchForAllClassroomMembers
    return if @destroyed # Don't do anything if page was destroyed after db request
    @updateLastPlayedString()
    @updateLevelProgressMap()
    @updateLevelDataMap()


  # onCourseInstancesSync: ->
  #   # @sessions = new CocoCollection([], { model: LevelSession })
  #   for courseInstance in @courseInstances.models
  #     sessions = new CocoCollection([], { url: "/db/course_instance/#{courseInstance.id}/level_sessions", model: LevelSession })
  #     @supermodel.loadCollection(sessions, { data: { project: ['level', 'playtime', 'creator', 'changed', 'state.complete'].join(' ') } })
  #     courseInstance.sessions = sessions
  #     sessions.courseInstance = courseInstance
  #     courseInstance.sessionsByUser = {}
  #     @listenToOnce sessions, 'sync', (sessions) ->
  #       @sessions.add(sessions.slice())
  #       for courseInstance in @courseInstances.models
  #         courseInstance.sessionsByUser = courseInstance.sessions.groupBy('creator')
  #
  #   # Generate course instance JIT, in the meantime have models w/out equivalents in the db
  #   for course in @courses.models
  #     query = {courseID: course.id, classroomID: @classroom.id}
  #     courseInstance = @courseInstances.findWhere(query)
  #     if not courseInstance
  #       courseInstance = new CourseInstance(query)
  #       @courseInstances.add(courseInstance)
  #       courseInstance.sessions = new CocoCollection([], {model: LevelSession})
  #       # sessions.courseInstance = courseInstance
  #       courseInstance.sessionsByUser = {}

  updateLastPlayedString: ->
    # Make sure all our data is loaded, @sessions may not even be intialized yet
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded and @user?.loaded

    # Use lodash to find the last session for our user, @sessions already sorted by changed date
    session = _.findLast @sessions.models, (s) => s.get('creator') is @user.id

    return unless session

    # Find course for this level session, for it's name
    # Level.original is the original id, used for level versioning, and connects levels to level sessions
    for versionedCourse in @classroom.get('courses') ? []
      for level in versionedCourse.levels
        if level.original is session.get('level').original
          # Found the level for our level session in the classroom versioned courses
          # Find the full course so we can get it's name
          course = _.find @courses.models, (c) => c.id is versionedCourse._id
          break

    # Find level for this level session, for it's name
    level = @levels.findWhere({original: session.get('level').original})

    # Update last played string based on what we found
    @lastPlayedString = ""
    @lastPlayedString += course.get('name') if course
    @lastPlayedString += ": " if course and level
    @lastPlayedString += level.get('name') if level
    @lastPlayedString += ", on " if course or level
    @lastPlayedString += moment(session.get('changed')).format("LLLL")
    # console.log (moment(session.get('changed')).format("LLLL"))
    # Rerun template/jade file to display new last played string
    @render()

  updateLevelProgressMap: ->
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded and @user?.loaded

    # Map levels to sessions once, so we don't have to search entire session list multiple times below
    @levelSessionMap = {}
    for session in @sessions.models when session.get('creator') is @studentID
      @levelSessionMap[session.get('level').original] = session


    # Create mapping of level to student progress
    @levelProgressMap = {}
    for versionedCourse in @classroom.get('courses') ? []
      for versionedLevel in versionedCourse.levels
        session = @levelSessionMap[versionedLevel.original]
        if session
          if session.get('state')?.complete
            @levelProgressMap[versionedLevel.original] = 'complete'
          else
            @levelProgressMap[versionedLevel.original] = 'started'
        else
          @levelProgressMap[versionedLevel.original] = 'not started'

  updateLevelDataMap: ->
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded

    @levelData = []
    for versionedCourse in @classroom.get('courses') ? []
      course = _.find @courses.models, (c) => c.id is versionedCourse._id
      for versionedLevel in versionedCourse.levels
        playTime = 0 # TODO: this and timesPlayed should probably only count when the levels are completed
        timesPlayed = 0
        studentTime = 0
        levelProgress = 'not started'
        for session in @sessions.models
          if session.get('level').original is versionedLevel.original
            # if @levelProgressMap[versionedLevel.original] == 'complete' # ideally, don't log sessions that aren't completed in the class
            playTime += session.get('playtime') or 0
            timesPlayed += 1
            if session.get('creator') is @studentID
              studentTime = session.get('playtime') or 0
              if @levelProgressMap[versionedLevel.original] is 'complete'
                levelProgress = 'complete'
              else if @levelProgressMap[versionedLevel.original] is 'started'
                levelProgress = 'started'
        classAvg = if timesPlayed > 0 then Math.round(playTime / timesPlayed) else 0 # only when someone other than the user has played
        # console.log (timesPlayed)
        @levelData.push {
          levelID: versionedLevel.original
          levelIndex: @classroom.getLevelNumber(versionedLevel.original)
          levelName: versionedLevel.name
          courseName: course.get('name')
          courseID: course.get('_id')
          classAvg: classAvg
          studentTime: if studentTime then studentTime else 0
          levelProgress: levelProgress
          # required:
        }
    # console.log (@levelData)

    # new map for averages of all classroom playtimes
    # @averageLevelPlaytimeMap = {}
    #   for versionedCourse in @classroom.get('courses') ? []
    #     for versionedLevel in versionedCourse.levels
    #       var totalPlaytime = null
    #       var totalSessions = 0
    #       session = @levelSessionMap[versionedLevel.original]
    #       # get playtimes for each session in all classroom sessions of this course with this particular level
    #       if totalPlaytime
    #         var averagePlaytime = totalPlaytime / totalSessions
    #         @averagePlaytimeMap[versionedLevel.original] = averagePlaytime

  studentStatusString: () ->
    status = @user.prepaidStatus()
    return "" unless @user.get('coursePrepaid')
    expires = @user.get('coursePrepaid')?.endDate
    string = switch status
      when 'not-enrolled' then $.i18n.t('teacher.status_not_enrolled')
      when 'enrolled' then (if expires then $.i18n.t('teacher.status_enrolled') else '-')
      when 'expired' then $.i18n.t('teacher.status_expired')
    if expires
      return string.replace('{{date}}', moment(expires).utc().format('l'))
    else
      # this probably doesn't happen
      return string.replace('{{date}}', "Never")


  # TODO: Hookup enroll/assign functionality

  # onClickEnrollStudentButton: (e) ->
  #   userID = $(e.currentTarget).data('user-id')
  #   user = @user.get(userID)
  #   selectedUsers = new Users([user])
  #   @enrollStudents(selectedUsers)
  #   window.tracker?.trackEvent $(e.currentTarget).data('event-action'), category: 'Teachers', classroomID: @classroom.id, userID: userID, ['Mixpanel']
  #
  # enrollStudents: (selectedUsers) ->
  #   modal = new ActivateLicensesModal { @classroom, selectedUsers, users: @user }
  #   @openModalView(modal)
  #   modal.once 'redeem-users', (enrolledUsers) =>
  #     enrolledUsers.each (newUser) =>
  #       user = @user.get(newUser.id)
  #       if user
  #         user.set(newUser.attributes)
  #     null



  # onLoaded: ->
  #   console.log("on loaded")
  #   for courseInstance in @courseInstances.models
  #     courseID = courseInstance.get('courseID')
  #     course = @courses.get(courseID)
  #     # courseInstance.sessions.course = course
  #   @updateLastPlayedString()
  #   super()
  #
  # afterRender: ->
  #   @$('[data-toggle="popover"]').popover({
  #     html: true
  #     trigger: 'hover'
  #     placement: 'top'
  #   })
  #   super()
  #
  # levelPopoverContent: (level, session, i) ->
  #   return null unless level
  #   context = {
  #     moment: moment
  #     level: level
  #     session: session
  #     i: i
  #     canViewSolution: @teacherMode
  #   }
  #   return popoverTemplate(context)
  #
  # getLevelURL: (level, course, courseInstance, session) ->
  #   return null unless @teacherMode and _.all(arguments)
  #   "/play/level/#{level.get('slug')}?course=#{course.id}&course-instance=#{courseInstance.id}&session=#{session.id}&observing=true"
