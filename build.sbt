import sbt.Keys.libraryDependencies

import scala.collection.Seq

ThisBuild / version := "0.1.0-SNAPSHOT"

Global / excludeLintKeys += idePackagePrefix
Global / excludeLintKeys += test / fork
Global / excludeLintKeys += run / mainClass

val scalaTestVersion = "3.2.11"
val guavaVersion = "31.1-jre"
val typeSafeConfigVersion = "1.4.2"
val logbackVersion = "1.2.10"
val sfl4sVersion = "2.0.0-alpha5"
val graphVizVersion = "0.18.1"
val netBuddyVersion = "1.14.4"
val catsVersion = "2.9.0"
val apacheCommonsVersion = "2.13.0"
val jGraphTlibVersion = "1.5.2"
val scalaParCollVersion = "1.0.4"
val guavaAdapter2jGraphtVersion = "1.5.2"
val circeVersion = "0.14.1"

lazy val commonDependencies = Seq(
  "org.scala-lang.modules" %% "scala-parallel-collections" % scalaParCollVersion,
  "org.scalatest" %% "scalatest" % scalaTestVersion % Test,
  "org.scalatestplus" %% "mockito-4-2" % "3.2.12.0-RC2" % Test,
  "io.circe" %% "circe-core" % "0.14.1",
  "io.circe" %% "circe-generic" % "0.14.1",
  "io.circe" %% "circe-parser" % "0.14.1",
  "com.typesafe" % "config" % typeSafeConfigVersion,
  "ch.qos.logback" % "logback-classic" % logbackVersion,
  "net.bytebuddy" % "byte-buddy" % netBuddyVersion,
  "io.circe" %% "circe-core" % circeVersion,
  "io.circe" %% "circe-generic" % circeVersion,
  "io.circe" %% "circe-parser" % circeVersion
).map(_.exclude("org.slf4j", "*"))


lazy val root = (project in file("."))
  .settings(
    scalaVersion := "3.2.2",
    name := "NetGameSim",
    idePackagePrefix := Some("com.lsc"),
    libraryDependencies ++= commonDependencies,
    libraryDependencies  ++= Seq("ch.qos.logback" % "logback-classic" % logbackVersion)
  ).aggregate(NetModelGenerator,GenericSimUtilities).dependsOn(NetModelGenerator)

lazy val NetModelGenerator = (project in file("NetModelGenerator"))
  .settings(
    scalaVersion := "3.2.2",
    name := "NetModelGenerator",
    libraryDependencies ++= commonDependencies ++ Seq(
      "com.google.guava" % "guava" % guavaVersion,
      "guru.nidi" % "graphviz-java" % graphVizVersion,
      "org.typelevel" %% "cats-core" % catsVersion,
      "commons-io" % "commons-io" % apacheCommonsVersion,
      "org.jgrapht" % "jgrapht-core" % jGraphTlibVersion,
      "org.jgrapht" % "jgrapht-guava" % guavaAdapter2jGraphtVersion,
    ),
    libraryDependencies  ++= Seq("ch.qos.logback" % "logback-classic" % logbackVersion)
  ).dependsOn(GenericSimUtilities)

lazy val GenericSimUtilities = (project in file("GenericSimUtilities"))
  .settings(
    scalaVersion := "3.2.2",
    name := "GenericSimUtilities",
    libraryDependencies ++= commonDependencies,
    libraryDependencies  ++= Seq("ch.qos.logback" % "logback-classic" % logbackVersion)
  )


scalacOptions ++= Seq(
      "-deprecation", // emit warning and location for usages of deprecated APIs
      "--explain-types", // explain type errors in more detail
      "-feature" // emit warning and location for usages of features that should be imported explicitly
    )

compileOrder := CompileOrder.JavaThenScala
test / fork := true
run / fork := true
run / javaOptions ++= Seq(
  "-Xms8G",
  "-Xmx100G",
  "-XX:+UseG1GC"
)

Compile / mainClass := Some("com.lsc.Main")
run / mainClass := Some("com.lsc.Main")

val jarName = "netmodelsim.jar"
assembly/assemblyJarName := jarName


//Merging strategies
ThisBuild / assemblyMergeStrategy := {
  case PathList("META-INF", _*) => MergeStrategy.discard
  case "reference.conf" => MergeStrategy.concat
  case _ => MergeStrategy.first
}

// -----------------------------
// Custom sbt task: mpiE2E
// Runs the end-to-end pipeline: generate graph -> partition -> build MPI runtime -> run leader and dijkstra
// Usage:
//   sbt mpiE2E
// Optional environment overrides:
//   RANKS=<n>   # default 10
//   SEED=<n>    # optional seed for graph generation
// On Windows it uses PowerShell scripts. On Linux/WSL/macOS it uses Bash/Python.
// -----------------------------
import scala.sys.process._

lazy val mpiE2E = taskKey[Unit]("Run end-to-end: graph export, partition, build MPI, run leader & dijkstra")

ThisBuild / mpiE2E := {
  val log = streams.value.log
  val root = (ThisBuild / baseDirectory).value
  val os = System.getProperty("os.name").toLowerCase

  val ranksEnv = sys.env.getOrElse("RANKS", "10")
  val seedEnv  = sys.env.get("SEED")

  val outputsDir = new java.io.File(root, "outputs"); outputsDir.mkdirs()
  val graphOut = new java.io.File(outputsDir, "graph.json").getAbsolutePath
  val partOut  = new java.io.File(outputsDir, "part.json").getAbsolutePath

  def runP(cmd: Seq[String]): Int = Process(cmd, root) ! log

  // Precompute task values outside of conditionals to satisfy sbt task linting
  val _ = (Compile / compile).value // ensure classes are compiled if needed later
  val cpEntries = (Compile / fullClasspath).value.map(_.data)

  if (os.contains("win")) {
    val pwsh = sys.env.getOrElse("POWERSHELL", "powershell")
    log.info("[mpiE2E] Generating graph via direct Java invocation (avoid nested sbt)")
    val configPath = new java.io.File(root, "GenericSimUtilities/src/main/resources/application.conf").getAbsolutePath
    val cpSep = java.io.File.pathSeparator
    val cpStr = cpEntries.map(_.getAbsolutePath).mkString(cpSep)
    val javaExe = sys.props.getOrElse("JAVA_EXE", {
      val jh = System.getProperty("java.home", "")
      val cand = if (jh.nonEmpty) new java.io.File(jh, "bin/java.exe") else new java.io.File("java")
      cand.getAbsolutePath
    })
    val sysProps = seedEnv match {
      case Some(s) if s.nonEmpty => Seq("-DNGSimulator.OutputGraphRepresentation.contentType=json", s"-Dconfig.file=${configPath}", s"-DNGSimulator.seed=${s}")
      case _ => Seq("-DNGSimulator.OutputGraphRepresentation.contentType=json", s"-Dconfig.file=${configPath}")
    }
    val javaCmd = Seq(javaExe) ++ sysProps ++ Seq("-cp", cpStr, "com.lsc.Main")
    val runRc = Process(javaCmd, root) ! log
    if (runRc != 0) sys.error("Graph export (Java run) failed")

    // Copy latest generated NetGraph_*.ngs from ./output to requested graphOut
    val outDir = new java.io.File(root, "output")
    val latestOpt: Option[java.io.File] = Option(outDir.listFiles()).toList.flatten
      .filter(f => f.getName.startsWith("NetGraph_") && f.getName.endsWith(".ngs"))
      .sortBy(_.lastModified())
      .lastOption
    latestOpt match {
      case Some(src) =>
        log.info(s"[mpiE2E] Using generated graph: ${src.getAbsolutePath}")
        val dest = new java.io.File(graphOut)
        dest.getParentFile.mkdirs()
        java.nio.file.Files.copy(src.toPath, dest.toPath, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
      case None => sys.error("No generated NetGraph_*.ngs file found in ./output after Java run")
    }

    // Partition via python (prefer 'py' launcher on Windows)
    val py = sys.env.getOrElse("PYTHON", "py")
    if (runP(Seq(py, new java.io.File(root, "tools/partition/run.py").getPath, graphOut, "--ranks", ranksEnv, "--out", partOut)) != 0)
      sys.error("Partitioning failed")

    // Detect native Windows MPI tools; if missing, fallback to WSL to run MPI steps
    def cmdExists(cmd: String): Boolean = {
      try { Process(Seq("where", cmd), root).!(ProcessLogger(_ => ())) == 0 } catch { case _: Throwable => false }
    }
    val forceWsl = sys.env.get("USE_WSL").exists(_.nonEmpty)
    val hasMpirun = cmdExists("mpirun")
    val hasMpicxx = cmdExists("mpicxx")

    if (forceWsl || !hasMpirun || !hasMpicxx) {
      log.warn("[mpiE2E] mpirun/mpicxx not found on Windows PATH (or USE_WSL set). Running MPI steps under WSL...")
      // Convert Windows path (e.g., E:\repo) to WSL (/mnt/e/repo)
      val abs = root.getAbsolutePath
      val drive = abs.substring(0,1).toLowerCase
      val rest = abs.substring(2).replace('\\','/')
      val wslRoot = s"/mnt/${drive}${rest}"
      val wsl = sys.env.getOrElse("WSL_EXE", "wsl.exe")
      // Run only the MPI steps under WSL to avoid invoking sbt again via WSL scripts
      val cmdLeader = s"cd ${wslRoot}; bash experiments/run_leader.sh"
      val rcLeader = Process(Seq(wsl, "bash", "-lc", cmdLeader), root) ! log
      if (rcLeader != 0) sys.error("WSL leader run failed")
      val cmdDij = s"cd ${wslRoot}; bash experiments/run_dijkstra.sh"
      val rcDij = Process(Seq(wsl, "bash", "-lc", cmdDij), root) ! log
      if (rcDij != 0) sys.error("WSL dijkstra run failed")
    } else {
      // Build and run leader/dijkstra via PS wrappers (they already auto-sync ranks to partition and oversubscribe)
      if (runP(Seq(pwsh, "-ExecutionPolicy", "Bypass", "-File", new java.io.File(root, "experiments/run_leader.ps1").getPath)) != 0)
        sys.error("Leader run failed")
      if (runP(Seq(pwsh, "-ExecutionPolicy", "Bypass", "-File", new java.io.File(root, "experiments/run_dijkstra.ps1").getPath)) != 0)
        sys.error("Dijkstra run failed")
    }
  } else {
    // Graph export via Bash
    val graphArgs = seedEnv match {
      case Some(s) if s.nonEmpty => Seq("bash", new java.io.File(root, "tools/graph_export/run.sh").getPath, "--out", graphOut, "--seed", s)
      case _ => Seq("bash", new java.io.File(root, "tools/graph_export/run.sh").getPath, "--out", graphOut)
    }
    if (runP(graphArgs) != 0) sys.error("Graph export failed")

    // Partition via python3
    if (runP(Seq("python3", new java.io.File(root, "tools/partition/run.py").getPath, graphOut, "--ranks", ranksEnv, "--out", partOut)) != 0)
      sys.error("Partitioning failed")

    // Build+run via Bash wrappers (auto rank sync & oversubscribe already present)
    if (runP(Seq("bash", new java.io.File(root, "experiments/run_leader.sh").getPath)) != 0)
      sys.error("Leader run failed")
    if (runP(Seq("bash", new java.io.File(root, "experiments/run_dijkstra.sh").getPath)) != 0)
      sys.error("Dijkstra run failed")
  }

  log.info("mpiE2E completed. See outputs/ for logs and summary JSON files.")
}